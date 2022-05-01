import json
import glob


def merge_templates():
    templates = []
    for path in glob.glob("stacks/*/template.json"):
        try:
            with open(path, "r") as json_template:
                template = json.load(json_template)
        except json.decoder.JSONDecodeError as e:
            raise ValueError(f"Can't parse {path}") from e
        if isinstance(template, dict):
            templates.append(template)
        elif isinstance(template, list):
            templates.extend(template)
        else:
            raise TypeError("Only dict and list are supported")
    final_json = {
        "version": "2",
        "templates": templates
    }
    with open("template.json", "w") as outfile:
        json.dump(final_json, outfile, indent=4)


if __name__ == "__main__":
    merge_templates()
