import json

input_file = "emby.list"
output_file = "emby.json"

rules = []
with open(input_file, 'r') as infile:
    for line in infile:
        line = line.strip()
        if not line:
            continue
        if line.startswith("DOMAIN-KEYWORD,"):
            keyword = line[len("DOMAIN-KEYWORD,"):]
            rules.append({"keyword": keyword})
        elif line.startswith("DOMAIN-SUFFIX,"):
            suffix = line[len("DOMAIN-SUFFIX,"):]
            rules.append({"suffix": suffix})
        elif line.startswith("DOMAIN,"):
            domain = line[len("DOMAIN,"):]
            rules.append({"domain": domain})
        else:
            # 如果没有匹配到任何前缀，则尝试作为纯域名处理
            rules.append({"domain": line})

output_data = {
    "version": 1,
    "rules": rules
}

with open(output_file, 'w') as outfile:
    json.dump(output_data, outfile, indent=2)

print(f"Successfully converted {input_file} to {output_file}")
