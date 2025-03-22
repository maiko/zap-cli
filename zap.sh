#!/usr/bin/env bash
# ------------------------------------------------------------------------------
# Zap — YAML-configurable, fuzzy-searchable, zero-bullsh*t SSH teleportation tool ⚡️
# ------------------------------------------------------------------------------
# Zap is a zero-bullsh*t SSH CLI built for infrastructure engineers who want
# speed, structure, and style in the terminal.
#
# It uses YAML-based configuration to organize your servers into categories,
# supports interactive fuzzy search, and handles aliases, ports, usernames,
# and exports with grace.
#
# Commands:
#   help                              Show this help message
#   version                           Show current version
#   add category                      Add a new category to your configuration
#   add host                          Add a new host under a category
#   list [<category>]                 List all categories (or filter by a specific one)
#   gen hosts [--write]               Generate an /etc/hosts block from your Zap config
#   export all                        Export full config (settings + categories) as a tgz archive
#   export settings                   Export only global settings as a tgz archive
#   export category <cat> [...]       Export one or more specific categories as a tgz archive
#   import <file.tgz>                 Import config from a tgz archive (merge mode)
#   search [<category>]               Launch interactive fuzzy search for hosts (optionally filtered)
#   <category> <host> [SSH opts]       Connect directly using category and host aliases
#
# Examples:
#   zap add category                 Add a new category
#   zap add host                     Add a host to a category
#   zap fw paris                     Connect to host 'paris' in category 'fw'
#   zap search fw                    Fuzzy search within the 'fw' category
#   zap gen hosts --write            Generate and write an /etc/hosts block (with backup)
#
# Requirements:
#   - Bash 4.x+
#   - yq v4.x (YAML processor)
#   - fzf (interactive search)
#   - ssh, ping
#
# Install tips:
#   • macOS: brew install yq fzf
#   • Linux: sudo apt remove yq && sudo wget https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -O /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq; also install fzf.
#
# Ready to teleport? Just type and go. ⚡️
# ------------------------------------------------------------------------------

# ----------------
# Version Constant
# ----------------
VERSION="v1.1.0 (2025-03-22)"

# If running under sudo, reset HOME to the original user’s home dir
if [[ "$EUID" -eq 0 && -n "$SUDO_USER" ]]; then
    export HOME=$(eval echo "~$SUDO_USER")
fi

# ================================
# Global Directories & Files
# ================================
CONFIG_DIR="${HOME}/.config/zap"
CATEGORIES_DIR="${CONFIG_DIR}/categories"
BACKUP_DIR="${CONFIG_DIR}/backups"
CONFIG_FILE="${CONFIG_DIR}/config.yml"  # Global config holds settings & category metadata

# ================================
# Global Defaults
# ================================
SSH_BIN="/usr/bin/ssh"
RETENTION_DAYS=7
ENABLE_WELCOME=false
LOGFILE=""

# ================================
# Utility: Check yq Version
# ================================
check_yq_version() {
    if ! yq --version 2>/dev/null | grep -q "v4"; then
         os=$(uname)
         echo -e "❌ Error: yq version 4.x is required. 😱"
         if [[ "$os" == "Darwin" ]]; then
             echo -e "👉 To fix this on macOS, run: brew install yq"
         else
             echo -e "👉 To fix this on Linux, run:"
             echo -e "   sudo apt remove yq && sudo wget https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64 -O /usr/local/bin/yq && sudo chmod +x /usr/local/bin/yq"
         fi
         exit 1
    fi
}

# ================================
# Initialization & Config Loading
# ================================
init_config() {
    mkdir -p "${CONFIG_DIR}" "${CATEGORIES_DIR}" "${BACKUP_DIR}"
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        cat <<EOF > "${CONFIG_FILE}"
ssh_bin: ${SSH_BIN}
enable_welcome: false
backup_retention_days: ${RETENTION_DAYS}
logging:
  enabled: false
  logfile: "${CONFIG_DIR}/zap.log"
categories: {}
EOF
    fi
}

load_config() {
    SSH_BIN_VAL=$(yq eval '.ssh_bin // ""' "${CONFIG_FILE}")
    if [[ -n "${SSH_BIN_VAL}" ]]; then
        SSH_BIN="${SSH_BIN_VAL}"
    fi
    ENABLE_WELCOME=$(yq eval '.enable_welcome // false' "${CONFIG_FILE}")
    RETENTION_DAYS=$(yq eval '.backup_retention_days // 7' "${CONFIG_FILE}")
    logging_enabled=$(yq eval '.logging.enabled // false' "${CONFIG_FILE}")
    if [[ "${logging_enabled}" == "true" ]]; then
        LOGFILE=$(yq eval '.logging.logfile // "'${CONFIG_DIR}/zap.log'"' "${CONFIG_FILE}")
    fi
}

# ================================
# Category Metadata Helper
# ================================
# Returns a delimiter-separated string: <emoji>|<default_user>|<default_port>
get_category_meta() {
    local cat_key="$1"
    local emoji default_user default_port
    emoji=$(yq eval ".categories.\"${cat_key}\".emoji // \"\"" "${CONFIG_FILE}")
    default_user=$(yq eval ".categories.\"${cat_key}\".default_user // \"\"" "${CONFIG_FILE}")
    default_port=$(yq eval ".categories.\"${cat_key}\".default_port // \"\"" "${CONFIG_FILE}")
    echo "${emoji}|${default_user}|${default_port}"
}

# ================================
# Backup & Logging Utilities
# ================================
backup_file() {
    local file="$1"
    if [[ -f "${file}" ]]; then
        local ts
        ts=$(date +"%Y%m%d-%H%M%S")
        cp "${file}" "${BACKUP_DIR}/$(basename "${file}").${ts}"
    fi
}

purge_backups() {
    find "${BACKUP_DIR}" -type f -mtime +${RETENTION_DAYS} -exec rm -f {} \;
}

log_msg() {
    local msg="$1"
    if [[ -n "${LOGFILE}" ]]; then
        echo "$(date +"%Y-%m-%d %H:%M:%S") - ${msg}" >> "${LOGFILE}"
    fi
}

# ================================
# Category & Host Management
# ================================
add_category() {
    echo -e "🚀 Enter the super cool category name (identifier, e.g., firewalls):"
    read -r cat_name
    if [[ -z "${cat_name}" ]]; then
        echo -e "❌ Oops! Category name cannot be empty. Try again! 😅"
        exit 1
    fi
    exists=$(yq eval ".categories.\"${cat_name}\"" "${CONFIG_FILE}")
    if [[ "${exists}" != "null" ]]; then
        echo -e "❌ Category '${cat_name}' already exists! 🙈"
        exit 1
    fi

    echo -e "🔍 Enter some aliases (comma-separated):"
    read -r alias_line
    IFS=',' read -ra alias_arr <<< "${alias_line}"
    trimmed_aliases=()
    for a in "${alias_arr[@]}"; do
        trimmed_aliases+=( "\"$(echo "${a}" | xargs)\"" )
    done
    aliases="[ $(IFS=,; echo "${trimmed_aliases[*]}") ]"

    echo -e "🎨 Enter an emoji for this category (optional, e.g., 🔥):"
    read -r emoji
    echo -e "👤 Enter a default username for this category (optional):"
    read -r def_user
    echo -e "💻 Enter a default SSH port (leave empty to let SSH decide):"
    read -r def_port

    backup_file "${CONFIG_FILE}"
    yq eval -i '.categories["'"${cat_name}"'"] = {"aliases": '"${aliases}"', "emoji": "'"${emoji}"'", "default_user": "'"${def_user}"'", "default_port": "'"${def_port}"'"}' "${CONFIG_FILE}"
    echo -e "✅ Category '${cat_name}' added in the global config! 🎉"

    local cat_file="${CATEGORIES_DIR}/${cat_name}.yml"
    if [[ ! -f "${cat_file}" ]]; then
        echo "hosts: {}" > "${cat_file}"
    fi
    purge_backups
}

add_host() {
    echo -e "🚀 Enter the category name where you'd like to add a host:"
    read -r cat_name
    exists=$(yq eval ".categories.\"${cat_name}\"" "${CONFIG_FILE}")
    if [[ "${exists}" == "null" ]]; then
        echo -e "❌ Category '${cat_name}' does not exist in the config! 😱"
        exit 1
    fi

    local cat_file="${CATEGORIES_DIR}/${cat_name}.yml"
    if [[ ! -f "${cat_file}" ]]; then
        echo -e "⚠️ No host file found for '${cat_name}'. Creating a new one! 🛠"
        echo "hosts: {}" > "${cat_file}"
    fi

    echo -e "🌐 Enter the primary hostname (identifier) for your device:"
    read -r host_key
    echo -e "📡 Enter the IP address (optional, leave blank to use the hostname for DNS resolution):"
    read -r ip_addr
    echo -e "👤 Enter the username (optional, leave empty to use category default):"
    read -r username
    echo -e "💻 Enter the SSH port (optional, leave empty to use category default):"
    read -r port
    echo -e "🔍 Enter host aliases (comma-separated, optional):"
    read -r host_alias_line
    IFS=',' read -ra host_alias_arr <<< "${host_alias_line}"
    trimmed_aliases=()
    for a in "${host_alias_arr[@]}"; do
        trimmed_aliases+=( "\"$(echo "${a}" | xargs)\"" )
    done
    aliases="[ $(IFS=,; echo "${trimmed_aliases[*]}") ]"

    backup_file "${cat_file}"
    yq eval -i '.hosts["'"${host_key}"'"] = {"ip": "'"${ip_addr}"'", "username": "'"${username}"'", "port": "'"${port}"'", "aliases": '"${aliases}"'}' "${cat_file}"
    echo -e "✅ Host '${host_key}' successfully added to category '${cat_name}'! 🎉"
    purge_backups
}

list_categories() {
    echo -e "🔍 Listing available categories and hosts:"
    # Optional filtering: if an argument is provided, list only that category.
    if [[ -n "$1" ]]; then
        cat_filter=$(resolve_category "$1")
        if [[ -z "${cat_filter}" ]]; then
            echo -e "❌ No category found matching '$1'."
            return 1
        fi
        categories="${cat_filter}"
    else
        categories=$(yq eval '.categories | keys | .[]' "${CONFIG_FILE}")
    fi
    for cat in $categories; do
        IFS='|' read -r emoji def_user def_port <<< "$(get_category_meta "${cat}")"
        if [[ -n "${def_user}" || -n "${def_port}" ]]; then
            echo -e "${emoji} ${cat} (default user: ${def_user}, port: ${def_port}):"
        else
            echo -e "${emoji} ${cat}:"
        fi

        local cat_file="${CATEGORIES_DIR}/${cat}.yml"
        if [[ ! -f "${cat_file}" ]]; then
            echo -e "   ⚠️  (No host file found)"
            continue
        fi
        host_keys=$(yq eval '.hosts | keys | .[]' "${cat_file}")
        if [[ -z "${host_keys}" ]]; then
            echo -e "   ⚠️  (No hosts found) 😅"
        else
            while read -r host; do
                aliases=$(yq eval '.hosts["'"${host}"'"].aliases | join(", ")' "${cat_file}")
                ip=$(yq eval ".hosts.\"${host}\".ip" "${cat_file}")
                if [[ -z "${ip}" || "${ip}" == "null" ]]; then
                    ip="${host}"
                fi
                eff_user=$(yq eval ".hosts.\"${host}\".username" "${cat_file}")
                [[ "$eff_user" == "null" ]] && eff_user=""
                eff_port=$(yq eval ".hosts.\"${host}\".port" "${cat_file}")
                if [[ "$eff_port" == "null" || "$eff_port" == "0" ]]; then eff_port=""; fi
                cat_default_user=$(yq eval ".categories.\"${cat}\".default_user" "${CONFIG_FILE}")
                cat_default_port=$(yq eval ".categories.\"${cat}\".default_port" "${CONFIG_FILE}")
                if [[ -z "$eff_user" ]]; then eff_user="$cat_default_user"; fi
                if [[ -z "$eff_port" ]]; then eff_port="$cat_default_port"; fi

                if [[ -n "$eff_user" || -n "$eff_port" ]]; then
                    printf "   - %s (%s): %s, user: %s, port: %s\n" "${host}" "${aliases}" "${ip}" "${eff_user}" "${eff_port}"
                else
                    printf "   - %s (%s): %s\n" "${host}" "${aliases}" "${ip}"
                fi
            done <<< "${host_keys}"
        fi
    done
}

# ================================
# Resolution Helpers
# ================================
resolve_category() {
    local input_alias="$1"
    local cats
    cats=$(yq eval '.categories | keys | .[]' "${CONFIG_FILE}")
    for cat in $cats; do
        if [[ "${cat}" == "${input_alias}" ]]; then
            echo "${cat}"
            return 0
        fi
        if yq eval ".categories.\"${cat}\".aliases[]" "${CONFIG_FILE}" 2>/dev/null | grep -q -w "${input_alias}"; then
            echo "${cat}"
            return 0
        fi
    done
    return 1
}

resolve_host() {
    local cat_file="$1"
    local input_alias="$2"
    host_keys=$(yq eval '.hosts | keys | .[]' "${cat_file}")
    for host in $host_keys; do
        if [[ "${host}" == "${input_alias}" ]]; then
            echo "${host}"
            return 0
        fi
    done
    for host in $host_keys; do
        if yq eval ".hosts.\"${host}\".aliases[]" "${cat_file}" 2>/dev/null | grep -q -w "${input_alias}"; then
            echo "${host}"
            return 0
        fi
    done
    return 1
}

# ================================
# SSH & Ping Operations
# ================================
run_ssh() {
    local cat_key="$1"
    local host_key="$2"
    shift 2
    local cat_file="${CATEGORIES_DIR}/${cat_key}.yml"

    local ip
    ip=$(yq eval ".hosts.\"${host_key}\".ip" "${cat_file}")
    if [[ -z "${ip}" || "${ip}" == "null" ]]; then
        ip="${host_key}"
    fi
    local host_user
    host_user=$(yq eval ".hosts.\"${host_key}\".username" "${cat_file}")
    [[ "$host_user" == "null" ]] && host_user=""
    local host_port
    host_port=$(yq eval ".hosts.\"${host_key}\".port" "${cat_file}")
    if [[ "$host_port" == "null" || "$host_port" == "0" ]]; then host_port=""; fi

    local cat_default_user
    cat_default_user=$(yq eval ".categories.\"${cat_key}\".default_user" "${CONFIG_FILE}")
    local cat_default_port
    cat_default_port=$(yq eval ".categories.\"${cat_key}\".default_port" "${CONFIG_FILE}")
    if [[ -z "$host_user" ]]; then host_user="$cat_default_user"; fi
    if [[ -z "$host_port" ]]; then host_port="$cat_default_port"; fi

    local target
    if [[ -n "$host_user" ]]; then
        target="${host_user}@${ip}"
    else
        target="${ip}"
    fi

    if [[ "${ENABLE_WELCOME}" == "true" ]]; then
        echo -e "⚡️⚡️⚡️   Zap Portal Activated   ⚡️⚡️⚡️"
        echo -e "🚀 Teleporting to '${host_key}' (${ip}) in category '${cat_key}'... Hang on tight! 😎"
    fi

    log_msg "SSH connect: category: ${cat_key}, host: ${host_key}, target: ${target}, ip: ${ip}, user: ${host_user}, port: ${host_port}"
    if [[ -n "$host_port" ]]; then
        exec "${SSH_BIN}" -p "${host_port}" "${target}" "$@"
    else
        exec "${SSH_BIN}" "${target}" "$@"
    fi
}

ping_host() {
    local ip="$1"
    echo -e "📡 Pinging ${ip}... Stand by for the signal! 🚀"
    ping -c 4 "${ip}"
}

# ================================
# Fuzzy Search Integration (Interactive Search)
# ================================
# If an extra parameter is provided, restrict the search to that category.
fuzzy_search() {
    if ! command -v fzf > /dev/null; then
        echo -e "❌ fzf not installed. Please install fzf to use interactive search. 😱"
        exit 1
    fi
    local filter_cat=""
    if [[ -n "$1" ]]; then
        filter_cat=$(resolve_category "$1")
        if [[ -z "${filter_cat}" ]]; then
            echo -e "❌ No category found matching '$1'. Proceeding with search over all categories."
        fi
    fi

    local choices=""
    if [[ -n "${filter_cat}" ]]; then
        local cat_file="${CATEGORIES_DIR}/${filter_cat}.yml"
        if [[ -f "${cat_file}" ]]; then
            for host in $(yq eval '.hosts | keys | .[]' "${cat_file}"); do 
                local ip=$(yq eval ".hosts.\"${host}\".ip" "${cat_file}")
                if [[ -z "${ip}" || "${ip}" == "null" ]]; then
                    ip="${host}"
                fi
                local aliases
                aliases=$(yq eval ".hosts.\"${host}\".aliases | join(\", \")" "${cat_file}")
                choices+="${filter_cat}|${host}|${aliases}|${ip}"$'\n'
            done
        fi
    else
        for cat in $(yq eval '.categories | keys | .[]' "${CONFIG_FILE}"); do 
            local cat_file="${CATEGORIES_DIR}/${cat}.yml"
            if [[ -f "${cat_file}" ]]; then
                for host in $(yq eval '.hosts | keys | .[]' "${cat_file}"); do 
                    local ip=$(yq eval ".hosts.\"${host}\".ip" "${cat_file}")
                    if [[ -z "${ip}" || "${ip}" == "null" ]]; then
                        ip="${host}"
                    fi
                    local aliases
                    aliases=$(yq eval ".hosts.\"${host}\".aliases | join(\", \")" "${cat_file}")
                    choices+="${cat}|${host}|${aliases}|${ip}"$'\n'
                done
            fi
        done
    fi

    local selection
    selection=$(echo "$choices" | fzf --header="Interactive search for hosts (format: category|host|aliases|ip)" --delimiter="|")
    if [[ -z "$selection" ]]; then
        echo -e "❌ No selection made. Exiting interactive search. 😅"
        exit 0
    fi
    IFS="|" read -r sel_cat sel_host sel_alias sel_ip <<< "$selection"
    run_ssh "${sel_cat}" "${sel_host}"
}

# ================================
# Export & Import Configuration
# ================================
# Export modes:
#   export all         -> Export entire config directory (settings + categories)
#   export settings    -> Export only the global settings (config.yml)
#   export category <cat> [<cat> ...] -> Export one or more specific categories
export_config() {
    local mode="$1"
    shift || true
    local export_file
    local tmpdir
    tmpdir=$(mktemp -d)
    case "$mode" in
        all|"")
            cp "${CONFIG_FILE}" "${tmpdir}/config.yml"
            cp -r "${CATEGORIES_DIR}" "${tmpdir}/categories"
            export_file="zap_export_all_$(date +%Y%m%d-%H%M%S).tgz"
            ;;
        settings)
            cp "${CONFIG_FILE}" "${tmpdir}/config.yml"
            export_file="zap_export_settings_$(date +%Y%m%d-%H%M%S).tgz"
            ;;
        category)
            mkdir -p "${tmpdir}/categories"
            for cat in "$@"; do
                resolved_cat=$(resolve_category "${cat}")
                if [[ -n "${resolved_cat}" ]]; then
                    cp "${CATEGORIES_DIR}/${resolved_cat}.yml" "${tmpdir}/categories/"
                else
                    echo -e "⚠️  Category '$cat' not found, skipping."
                fi
            done
            export_file="zap_export_category_$(date +%Y%m%d-%H%M%S).tgz"
            ;;
        *)
            echo -e "❌ Unknown export mode. Use: all, settings, or category"
            rm -rf "${tmpdir}"
            exit 1
            ;;
    esac
    tar czf "${export_file}" -C "${tmpdir}" .
    rm -rf "${tmpdir}"
    echo -e "✅ Exported configuration to ${export_file}"
}

# Import: Merge the imported tgz into the current configuration.
import_config() {
    local import_file="$1"
    if [[ ! -f "${import_file}" ]]; then
        echo -e "❌ Import file '${import_file}' not found! Please check the path. 😱"
        exit 1
    fi
    local tmpdir
    tmpdir=$(mktemp -d)
    tar xzf "${import_file}" -C "${tmpdir}"
    # Merge global settings if present.
    if [[ -f "${tmpdir}/config.yml" ]]; then
        backup_file "${CONFIG_FILE}"
        yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${CONFIG_FILE}" "${tmpdir}/config.yml" > "${CONFIG_FILE}.merged"
        mv "${CONFIG_FILE}.merged" "${CONFIG_FILE}"
        echo -e "✅ Global settings updated."
    fi
    # Merge category files.
    if [[ -d "${tmpdir}/categories" ]]; then
        for file in "${tmpdir}/categories/"*.yml; do
            local cat
            cat=$(basename "$file")
            if [[ -f "${CATEGORIES_DIR}/${cat}" ]]; then
                backup_file "${CATEGORIES_DIR}/${cat}"
                yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${CATEGORIES_DIR}/${cat}" "$file" > "${CATEGORIES_DIR}/${cat}.merged"
                mv "${CATEGORIES_DIR}/${cat}.merged" "${CATEGORIES_DIR}/${cat}"
                echo -e "✅ Updated category ${cat%.*}."
            else
                cp "$file" "${CATEGORIES_DIR}/"
                echo -e "✅ Imported new category ${cat%.*}."
            fi
        done
    fi
    rm -rf "${tmpdir}"
    load_config
    echo -e "✅ Import complete and configuration updated."
}

# ================================
# Dynamic Autocompletion
# ================================
if ! type _init_completion >/dev/null 2>&1; then
  _init_completion() {
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    words=("${COMP_WORDS[@]}")
    cword="${COMP_CWORD}"
  }
fi

_zap_completions() {
    local cur prev words cword
    _init_completion || return

    local opts=""
    local cats
    cats=$(yq eval '.categories | keys | .[]' "${CONFIG_FILE}")
    for cat in $cats; do
        opts+="${cat} "
        local cat_aliases
        cat_aliases=$(yq eval ".categories.\"${cat}\".aliases[]" "${CONFIG_FILE}" 2>/dev/null)
        opts+="${cat_aliases} "
        local cat_file="${CATEGORIES_DIR}/${cat}.yml"
        if [[ -f "${cat_file}" ]]; then
            local hosts
            hosts=$(yq eval '.hosts | keys | .[]' "${cat_file}")
            opts+="${hosts} "
        fi
    done
    COMPREPLY=( $(compgen -W "${opts}" -- "${cur}") )
}
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    complete -F _zap_completions zap
fi

# ================================
# Generate /etc/hosts Block
# ================================
# ================================
# Generate /etc/hosts Block
# ================================
gen_hosts() {
    local write_flag=false
    if [[ "$1" == "--write" ]]; then
        write_flag=true
        shift
    fi

    if [[ $# -gt 0 ]]; then
        echo "❌ [ERROR] Too many arguments. Usage: zap gen hosts [--write]" >&2
        exit 1
    fi

    local block=""
    block+="# ZAP-BEGIN\n"
    local found_any=false

    for cat in $(yq eval '.categories | keys | .[]' "${CONFIG_FILE}"); do
        local cat_file="${CATEGORIES_DIR}/${cat}.yml"
        [[ ! -f "${cat_file}" ]] && continue

        block+="## ${cat}\n"
        local cat_has=false

        for host in $(yq eval '.hosts | keys | .[]' "${cat_file}"); do
            local ip
            ip=$(yq eval ".hosts.\"${host}\".ip" "${cat_file}")
            if [[ -z "${ip}" || "${ip}" == "null" ]]; then
                echo "⚠️ Host '${host}' in category '${cat}' has no IP defined — skipping" >&2
                continue
            fi
            local aliases
            aliases=$(yq eval ".hosts.\"${host}\".aliases | join(\" \")" "${cat_file}" | xargs)
            block+="${ip}\t${host} ${aliases}\n"
            cat_has=true
            found_any=true
        done

        if ! $cat_has; then
            block+="(No hosts with IP defined)\n"
        fi
        block+="\n"
    done

    block+="# ZAP-END"

    if ! $found_any; then
        echo "⚠️ No hosts with IP defined in the configuration." >&2
        log_msg "WARN: No IPs found in config during gen_hosts"
        return 1
    fi

    echo "🔧 Generated hosts block from Zap config"
    log_msg "Generated /etc/hosts block from Zap config"

    if ! $write_flag; then
        echo -e "${block}"
        return 0
    fi

    if [[ ! -w /etc/hosts ]]; then
        echo "❌ [ERROR] Insufficient permissions to write to /etc/hosts" >&2
        log_msg "ERROR: Cannot write to /etc/hosts"
        
        # Get the full path to the current zap script
        local zap_path
        zap_path="$(realpath "$0" 2>/dev/null || readlink -f "$0" 2>/dev/null)"
        if [[ -n "${zap_path}" ]]; then
            echo "💡 Try: sudo ${zap_path} gen hosts --write"
        else
            echo "💡 Try running the same command with sudo and the full path to zap"
        fi
        exit 1
    fi

    local backup_file_path="${BACKUP_DIR}/hosts.$(date +%Y%m%d-%H%M%S).bak"
    cp /etc/hosts "${backup_file_path}"
    echo "💾 /etc/hosts backup saved to: ${backup_file_path}"
    log_msg "/etc/hosts backup saved to ${backup_file_path}"

    tmpfile=$(mktemp)

    awk '
        BEGIN { zap=0 }
        /# ZAP-BEGIN/ { zap=1; next }
        /# ZAP-END/ { zap=0; next }
        zap == 0 { print }
        ' /etc/hosts > "$tmpfile"

    echo -e "${block}" >> "$tmpfile"

    cp "$tmpfile" /etc/hosts
    rm -f "$tmpfile"

    if grep -q "# ZAP-BEGIN" "$backup_file_path"; then
        echo "🔁 [OK] Replaced existing Zap block in /etc/hosts"
        log_msg "OK: Replaced existing Zap block"
    else
        echo "➕ [OK] Added Zap block to /etc/hosts"
    fi

    return 0
}

# ================================
# Main Command Parser & Usage
# ================================
usage() {
    cat <<EOF
⚡️  Usage: zap <command> [arguments...]

Zap is your zero-bullsh*t SSH CLI for infra engineers.
Manage your server categories and hosts with YAML config, fuzzy search, and direct teleportation.

Commands:
  help                              Show this help message
  version                           Show Zap version information
  add category                      Add a new category (emoji, user, port, aliases)
  add host                          Add a new host under a category
  list [<category>]                 List all categories (or filter by a specific category)
  gen hosts [--write]               Generate an /etc/hosts block from Zap config
  export all                        Export full config (settings + categories) as .tgz
  export settings                   Export global settings as .tgz
  export category <cat> [...]       Export one or more specific categories as .tgz
  import <file.tgz>                 Import config from a .tgz archive (merge mode)
  search [<category>]               Launch interactive fuzzy search for hosts
  <category> <host> [SSH opts]        Direct SSH to host (aliases supported, add --ping to test reachability)

Examples:
  zap add category                 Add a new category
  zap add host                     Add a host to a category
  zap fw paris                     Connect to host "paris" in category "fw"
  zap search fw                    Fuzzy search within the "fw" category
  zap gen hosts                    Generate a hosts block (print to stdout)
  zap gen hosts --write            Write hosts block to /etc/hosts (with backup)
  zap export category firewalls    Export the "firewalls" category
  zap import backup_20250322.tgz   Merge config from a backup archive

EOF
}

main() {
    check_yq_version
    init_config
    load_config

    if [[ $# -lt 1 ]]; then
        usage
        exit 0
    fi

    command="$1"
    shift

    case "$command" in
        help)
            usage
            ;;
        version)
            echo "Zap version ${VERSION}"
            ;;
        add)
            if [[ "$1" == "category" ]]; then
                shift
                add_category
            elif [[ "$1" == "host" ]]; then
                shift
                add_host
            else
                echo -e "❌ Unknown add command. Use: zap add category|host"
                usage
                exit 1
            fi
            ;;
        list)
            list_categories "$1"
            ;;
        gen)
            if [[ "$1" == "hosts" ]]; then
                shift
                gen_hosts "$@"
            else
                echo -e "❌ Unknown gen command. Use: zap gen hosts [--write]"
                usage
                exit 1
            fi
            ;;
        export)
            if [[ -z "$1" ]]; then
                echo -e "❌ Please specify export mode: all, settings, or category"
                exit 1
            fi
            export_config "$@"
            ;;
        import)
            if [[ -z "$1" ]]; then
                echo -e "❌ Please provide a file to import!"
                exit 1
            fi
            import_config "$1"
            ;;
        search)
            fuzzy_search "$@"
            ;;
        *)
            # Default: direct SSH connection: first argument is category alias, second is host alias.
            if [[ $# -lt 1 ]]; then
                echo -e "❌ Error: You must supply both a category alias and a host alias! 😅"
                usage
                exit 1
            fi
            category_alias="$command"
            host_alias="$1"
            shift 1
            for arg in "$@"; do
                if [[ "$arg" == "--ping" ]]; then
                    ping_mode=true
                    break
                fi
            done
            cat_key=$(resolve_category "${category_alias}")
            if [[ -z "${cat_key}" ]]; then
                echo -e "❌ Category '${category_alias}' not found in config! 🙈"
                exit 1
            fi
            local cat_file="${CATEGORIES_DIR}/${cat_key}.yml"
            if [[ ! -f "${cat_file}" ]]; then
                echo -e "❌ No host file found for category '${cat_key}'! 😱"
                exit 1
            fi
            host_key=$(resolve_host "${cat_file}" "${host_alias}")
            if [[ -z "${host_key}" ]]; then
                echo -e "❌ Host '${host_alias}' not found in category '${cat_key}'! 🤷‍♂️"
                exit 1
            fi
            if [[ "${ping_mode}" == true ]]; then
                ip=$(yq eval ".hosts.\"${host_key}\".ip" "${cat_file}")
                if [[ -z "${ip}" || "${ip}" == "null" ]]; then
                    ip="${host_key}"
                fi
                ping_host "${ip}"
            else
                run_ssh "${cat_key}" "${host_key}" "$@"
            fi
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi