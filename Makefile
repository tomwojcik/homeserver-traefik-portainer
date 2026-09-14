.PHONY: merge-templates create-volumes


merge-templates:
	python scripts/merge_templates.py

create-volumes:
	python scripts/create_volumes.py
