#!/usr/bin/env python3
import re
import sys
import json
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import argparse

class RuleProcessor:
    """
    Processes rule lists (like emby.list), specifically filtering redundant
    DOMAIN-SUFFIX rules (removing subdomains if the parent domain suffix exists).
    Generates an updated .list file and a .json file compatible with sing-box.
    """
    # Defines the preferred order for rule types in the output .list file and header stats.
    TYPE_ORDER = ["DOMAIN", "DOMAIN-KEYWORD", "DOMAIN-SUFFIX", "IP-CIDR"]
    # Maps internal rule types to the keys used in the sing-box JSON output.
    JSON_MAP = {"DOMAIN": "domain", "DOMAIN-KEYWORD": "domain_keyword",
                "DOMAIN-SUFFIX": "domain_suffix", "IP-CIDR": "ip_cidr"}

    def __init__(self, input_file, output_json):
        """Initializes the processor with input and output file paths."""
        self.input_file = Path(input_file)
        self.output_json = Path(output_json)
        # Stores rules grouped by type (e.g., self.rules['DOMAIN-SUFFIX'] = {'example.com', ...})
        self.rules = defaultdict(set)

    def _load_content(self):
        """Loads rule content from the input file, skipping the header."""
        try:
            with open(self.input_file, encoding="utf-8") as f:
                content = f.read()
            # Find header block (# NAME: ... until first non-# line or EOF) and remove it
            header_match = re.search(r"^# NAME:.*?(?=\n[^#]|\Z)", content, re.DOTALL)
            if header_match:
                return content[len(header_match.group(0)):].lstrip('\n')
            return content # Return full content if no header found
        except FileNotFoundError:
            print(f"Error: Input file '{self.input_file}' not found.")
            sys.exit(1)
        except Exception as e:
            print(f"Error reading input file '{self.input_file}': {e}")
            sys.exit(1)

    def _parse_line(self, line):
        """Parses a single line into a rule dictionary {'type': TYPE, 'value': VALUE}."""
        line = line.strip()
        # Ignore empty lines and comments
        if not line or line.startswith("#"):
            return None

        # Match explicitly typed rules (e.g., "DOMAIN-SUFFIX, example.com")
        # Case-insensitive type matching, comma or whitespace separator
        type_pattern = rf"^({'|'.join(self.TYPE_ORDER)})[,\s]+([^#\s]+)"
        match = re.match(type_pattern, line, re.I)
        if match:
            # Convert type to uppercase, value to lowercase
            return {"type": match.group(1).upper(), "value": match.group(2).lower()}

        # Handle implicitly typed rules (lines without a type prefix)
        # Basic check for a potential domain/hostname format
        # Assumes such lines should be treated as DOMAIN type
        if re.match(r"^[a-zA-Z0-9.-]+$", line):
             return {"type": "DOMAIN", "value": line.lower()} # Defaulting to DOMAIN

        # Optional: Warn about lines that couldn't be parsed
        # print(f"Warning: Skipping unparseable line: {line}")
        return None # Return None for lines that don't match expected formats

    def _filter_redundant_suffixes(self, suffixes):
        """
        Removes domain suffixes that are subdomains of other suffixes present in the input set.
        Example: If 'example.com' and 'sub.example.com' are present, removes 'sub.example.com'.
        """
        if not suffixes: # Handle empty input
            return set()

        # Sort by length (shorter first) to potentially optimize checks
        sorted_suffixes = sorted(list(suffixes), key=len)
        redundant = set() # Store suffixes identified as redundant

        for i, s1 in enumerate(sorted_suffixes):
            # Skip if s1 already marked redundant by a broader (shorter) suffix checked earlier
            if s1 in redundant:
                continue
            # Check s1 against all subsequent (longer, potential subdomains) suffixes
            for j in range(i + 1, len(sorted_suffixes)):
                s2 = sorted_suffixes[j]
                # Check if s2 (e.g., sub.example.com) ends with '.<s1>' (e.g., .example.com)
                if s2.endswith('.' + s1):
                     # s2 is redundant because s1 is broader and also present
                    redundant.add(s2)

        # Return the original set minus the identified redundant suffixes
        return suffixes - redundant

    def _generate_header(self, stats):
        """Generates the header block for the .list file with metadata and rule counts."""
        now_utc = datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')
        # Static header information
        header_lines = [
            "# NAME: Emby", # Consider making this dynamic if needed
            "# AUTHOR: KuGouGo", # Consider making this dynamic if needed
            "# REPO: https://github.com/KuGouGo/Rules", # Consider making this dynamic if needed
            f"# UPDATED: {now_utc}",
        ]
        total = 0
        # Add counts for each rule type present, following TYPE_ORDER
        all_present_types = set(stats.keys())
        types_in_order = self.TYPE_ORDER + [t for t in all_present_types if t not in self.TYPE_ORDER]

        for rule_type in types_in_order:
             count = stats.get(rule_type, 0)
             if count > 0:
                 header_lines.append(f"# {rule_type}: {count}")
                 total += count

        header_lines.append(f"# TOTAL: {total}")
        header_lines.append("") # Blank line after stats
        return "\n".join(header_lines) + "\n" # Ensure trailing newline for the block

    def process(self):
        """Main processing logic: loads, parses, filters, sorts, and writes rules."""
        content = self._load_content()

        # Parse all lines from the content
        parsed_rules_list = []
        for line in content.splitlines():
            parsed = self._parse_line(line)
            if parsed:
                parsed_rules_list.append(parsed) # Keep all successfully parsed rules

        # Group parsed rules by type into self.rules (using defaultdict(set))
        self.rules = defaultdict(set)
        for r in parsed_rules_list:
            self.rules[r["type"]].add(r["value"])

        # Apply the specific filtering for DOMAIN-SUFFIX rules
        if "DOMAIN-SUFFIX" in self.rules:
            original_suffix_count = len(self.rules["DOMAIN-SUFFIX"])
            filtered_suffixes = self._filter_redundant_suffixes(self.rules["DOMAIN-SUFFIX"])
            removed_count = original_suffix_count - len(filtered_suffixes)
            if removed_count > 0:
                print(f"Filtered {removed_count} redundant DOMAIN-SUFFIX rule(s).")
            # Update the stored rules with the filtered set
            self.rules["DOMAIN-SUFFIX"] = filtered_suffixes

        # Prepare the sorted list of rules for the output .list file and calculate final stats
        sorted_rules_list_output = []
        stats = defaultdict(int)
        # Ensure all present types are processed, respecting TYPE_ORDER preference
        all_types_present = set(self.rules.keys())
        type_processing_order = self.TYPE_ORDER + [t for t in all_types_present if t not in self.TYPE_ORDER]

        for t in type_processing_order:
            # Process only if the type exists and has rules after potential filtering
            if t in self.rules and self.rules[t]:
                sorted_values = sorted(list(self.rules[t])) # Sort values alphabetically
                stats[t] = len(sorted_values) # Store final count for this type
                # Format rules as "TYPE,value" for the .list file
                sorted_rules_list_output.extend(f"{t},{v}" for v in sorted_values)

        # Generate the header using the final stats
        header = self._generate_header(stats)

        # Write the updated .list file (header + sorted rules)
        try:
            with open(self.input_file, "w", encoding="utf-8") as f:
                f.write(header)
                f.write("\n".join(sorted_rules_list_output))
                f.write("\n") # Ensure a trailing newline at the end of the file
        except Exception as e:
            print(f"Error writing to input file '{self.input_file}': {e}")
            sys.exit(1) # Critical error, stop execution

        # Prepare the data structure for the output .json file (for sing-box)
        output_json_rules_list = [] # The "rules" field in JSON is a list of rule objects
        rule_entry = {} # A single rule object containing different types
        has_rules_in_entry = False
        # Map internal types to JSON keys using JSON_MAP
        for rule_type_internal, json_key in self.JSON_MAP.items():
            # Check if the type exists and has rules after filtering
            if rule_type_internal in self.rules and self.rules[rule_type_internal]:
                # Sort values for consistent JSON output
                sorted_values = sorted(list(self.rules[rule_type_internal]))
                rule_entry[json_key] = sorted_values
                has_rules_in_entry = True # Mark that this entry has data

        # Add the populated rule_entry to the list if it contained any rules
        if has_rules_in_entry:
             output_json_rules_list.append(rule_entry)

        # Final JSON structure adhering to sing-box format (version 3)
        json_data = {"version": 3, "rules": output_json_rules_list}

        # Write the .json file
        try:
            with open(self.output_json, "w", encoding="utf-8") as f:
                # Use indent=2 for pretty-printing the JSON
                json.dump(json_data, f, indent=2)
        except Exception as e:
            print(f"Error writing to output JSON file '{self.output_json}': {e}")
            # Consider if this failure should also cause script exit
            # sys.exit(1)

# Entry point for script execution
if __name__ == "__main__":
    # Setup command-line argument parsing
    parser = argparse.ArgumentParser(
        description="Process rule list, filter redundant DOMAIN-SUFFIX, generate sing-box JSON."
    )
    parser.add_argument(
        "input_file",
        nargs="?", # Argument is optional
        default="emby.list", # Default value if not provided
        help="Input rule list file (default: emby.list)"
    )
    parser.add_argument(
        "output_json",
        nargs="?", # Argument is optional
        default="emby.json", # Default value if not provided
        help="Output JSON file for sing-box (default: emby.json)"
    )
    args = parser.parse_args() # Parse arguments from command line

    # Create processor instance and run the process
    RuleProcessor(args.input_file, args.output_json).process()