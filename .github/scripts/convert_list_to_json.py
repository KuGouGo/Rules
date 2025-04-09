import json

input_file = "emby.list"
output_file = "emby.json"

with open(input_file, 'r') as infile, open(output_file, 'w') as outfile:
    for line in infile:
        domain = line.strip()
        if domain:
            json_object = {"domain": domain}
            json.dump(json_object, outfile)
            outfile.write('\n')

print(f"Successfully converted {input_file} to {output_file}")
