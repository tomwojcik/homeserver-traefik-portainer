.PHONY: merge-templates create-volumes sync


merge-templates:
	python scripts/merge_templates.py

create-volumes:
	python scripts/create_volumes.py

# Redeploy the stacks running on this host from this checkout (run after git pull). Pass -y with: make sync ARGS=-y
sync:
	sudo bash scripts/sync-stacks.sh $(ARGS)
