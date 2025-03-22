
.PHONY: install update uninstall link help

ZAP_NAME=zap
ZAP_BIN=~/bin/$(ZAP_NAME)
ZAP_SRC=zap.sh

install:
	@echo "🚀 Installing $(ZAP_NAME) to $(ZAP_BIN)"
	mkdir -p ~/bin
	cp $(ZAP_SRC) $(ZAP_BIN)
	chmod +x $(ZAP_BIN)
	@echo "✅ Done! Run it with: $(ZAP_NAME)"

update:
	@echo "⬆️  Updating $(ZAP_NAME)..."
	cp $(ZAP_SRC) $(ZAP_BIN)
	chmod +x $(ZAP_BIN)
	@echo "🔄 Updated!"

package:
	@echo "📦 Exporting current config..."
	$(ZAP_BIN) export all > /dev/null
	@exported_file=$$(ls -t zap_export_all_$(shell date +%Y%m%d)*.tgz | head -n1); \
	@echo "📦 Exported config saved as: $$exported_file"

link:
	ln -sf $(PWD)/$(ZAP_SRC) $(ZAP_BIN)
	@echo "🔗 Symlinked $(ZAP_SRC) → $(ZAP_BIN)"

sync:
	@echo "📂 Syncing current config to Git..."
	git add .
	git commit -m '🔄 Sync Zap config update'
	git push
	@echo "🔄 Synced!"

uninstall:
	rm -f $(ZAP_BIN)
	@echo "❌ Uninstalled $(ZAP_NAME) from $(ZAP_BIN)"

help:
	@echo "🛠️  Available commands:"
	@grep -E '^[a-zA-Z_-]+:' Makefile | cut -d: -f1 | sed 's/^/ - /'
