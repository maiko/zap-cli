# ⚡️ Zap
![Zap version](https://img.shields.io/badge/version-v1.0.0-blueviolet?style=flat-square)
![Made With Bash](https://img.shields.io/badge/Made%20with-Bash-1f425f?style=flat-square)
![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)

![GitHub release](https://img.shields.io/github/v/release/maiko/zap-cli?style=flat-square)

**Version:** v1.0.0 (2025-03-22)  
**Language:** Bash  
**Install path:** `~/bin/zap`  
**Dependencies:** `yq (v4.x)`, `fzf`, `ssh`, `ping`

---

## ⚡️ What is Zap?

**Zap** is a zero-bullsh*t SSH CLI built for infrastructure engineers who want speed, structure, and style in the terminal.

With YAML-based configuration and interactive fuzzy search, Zap makes jumping into any server fast, fun, and ridiculously efficient.  
Forget boring SSH commands — just `zap fw paris` or `zap search` and teleport to your servers with style 😎

---

## ✨ Features

- 🔖 YAML config per category (firewalls, switches, etc)
- 🔍 Fuzzy search with `fzf`, category filtering
- 👤 Custom SSH user/port per host or category
- 🔁 Interactive `add category`, `add host` CLI flows
- 💾 Auto backups with purge system
- 📄 Import/export entire or partial configuration (as .tgz archives)
- 🧠 Alias resolution for both categories and hosts
- 🎯 Direct usage: `zap <category> <host> [--ping | SSH opts]`
- 🧩 Autocompletion support

---

## ⚡️ Quickstart

```bash
make install     # Install Zap to ~/bin/zap
zap add category # Start configuring
zap add host     # Add your first host
zap list         # See what's in your config
zap fw myhost    # And boom, you're in 😎
```

---

## 🛠️ Installation (Dev Mode)

```bash
make install     # Copy zap.sh into ~/bin/zap
make link        # Symlink for live dev mode
make update      # Push updates to ~/bin
make uninstall   # Remove from your system
```

---

## ⚙️ Commands

```bash
zap help                          # Show usage
zap version                       # Display current version
zap add category                  # Add new category (with emoji, user, port)
zap add host                      # Add host under a category
zap list [<category>]             # Show hosts by category
zap search [<category>]           # Interactive fuzzy search
zap export all                    # Export entire config as .tgz
zap export settings               # Export only global settings
zap export category <cat> [...]   # Export selected categories
zap import <file.tgz>             # Import and merge from a .tgz archive
zap <cat> <host> [opts]           # SSH into a host or ping (add --ping)
```

---

## 📁 Where Zap stores stuff

Zap keeps its config in:

```
~/.config/zap/
├── config.yml               # global settings & category metadata
├── categories/              # one YAML file per category
├── backups/                 # automatic versioned backups
```

---

## 🔒 Example: config.yml

```yaml
categories:
  firewalls:
    emoji: 🔥
    default_user: admin
    default_port: 22
    aliases: [fw, firewall]
```

### And `categories/firewalls.yml`:

```yaml
hosts:
  paris-fw-1:
    ip: 1.1.1.1
    username: admin
    port: 22
    aliases:
      - paris
      - paris-fw1
      - pfw1
```

---

## 📦 Import / Export Examples

Export everything:
```bash
zap export all
```

Export just global config:
```bash
zap export settings
```

Export only specific categories:
```bash
zap export category firewalls switches
```

Import from a file:
```bash
zap import team_zap_config.tgz
```

---

Designed for fun, in France, by Maiko BOSSUYT.
