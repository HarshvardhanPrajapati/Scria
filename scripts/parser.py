import re #regular expression
import json
import os
import sys

OUTPUT_DIR = "DataIndex/raw_index"

def read_file(filepath): #utility function to read file content
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            return f.read()
    except FileNotFoundError:
        print(f"File not found at {filepath}", file = sys.stderr)
        return None
    except Exception as e:
        print(f"Error reading file at {filepath}; {e}", file = sys.stderr)
        return None
    
#core solidity parsing logic
def parse_solidity_functions(code):
    functions = {}
    function_pattern = r'function\s+([a-zA-Z0-9_]+)\s*\(.*?\).*?\{.*?\}' #function regular expression

    for match in re.finditer(function_pattern, code, re.DOTALL): #for each time a function_pattern is found in code
        full_code_block = match.group(0).strip() #the whole matching function code

        name_match = re.search(r'function\s+([a-zA-Z0-9_]+)', full_code_block) #r'function\s+([a-zA-Z0-9_]+)' => this gives 'function <function name>'
        if(name_match):
            func_name = name_match.group(1) #the function name
            functions[func_name] = full_code_block #map the full code to function's name

    return functions

#parsing them CVL properties
def parse_cvl_properties(code):
    properties = [] #list of dictionaries

    rule_pattern = r'(rule\s+([a-zA-Z0-9_]+)\s*\{.*?\}\n)' #rule RE
    for match in re.finditer(rule_pattern, code, re.DOTALL):
        properties.append({
            "type":"RULE",
            "name":match.group(2),
            "body":match.group(1).strip()
        })
    
    invariant_pattern = r'(invariant\s+([a-zA-Z0-9_]+)\s*\([^)]*\)\s*(.*?);)' #REGEX for invariantes
    for match in re.finditer(invariant_pattern, code, re.DOTALL): #captures full invariant defination and name
        properties.append({
            "type":"INVARIANT",
            "name":match.group(2),
            "body":match.group(1).strip()
        })

    return properties

#function to link CVL property to its target function, VERY IMP, returns set of target functions linked to that property
def determine_target_function(prop_body, all_solidity_functions):
    target_fncs = set()
    body_lower = prop_body.lower()
    all_func_names = [name.lower() for name in all_solidity_functions.keys()]

    for func in all_func_names:
        if f"{func}(" in body_lower or f"{func}@" in body_lower: #check for function call syntax
            target_fncs.add(func)
    
    #make invariant global if no specific function are called
    if not target_fncs and "invariant" in body_lower:
        return "ALL"

    return "/".join(sorted(list(target_fncs))) or "UNKNOWN"

#actually creating the JSONs that we wil be storing in out vector database
def create_index_records(solidity_functions, formal_properties, full_sol_code, source_contract_name):
    records = []

    #full contraact data
    records.append({
        "id":f"{source_contract_name.replace('.sol','')}_contract_context", 
        "chunk_type":"CONTRACT_CONTEXT",
        "source_contract":source_contract_name,
        "target_function":"ALL",
        "text_chunk":full_sol_code,
        "formal_property":None,
        "nl_summary":"",
        "metadata":{"function_list":list(solidity_functions.keys()), "is_standard":"UNKNOWN"}
    })

    #property specific data
    for prop in formal_properties:
        target_func_str = determine_target_function(prop['body'],solidity_functions)
        solcode_chunk = ""
        target_func_name = target_func_str.split('/')[0] #use first linked function for chunk lookup

        if target_func_name == "ALL":
            solcode_chunk = full_sol_code
        elif target_func_name in solidity_functions:
            solcode_chunk = solidity_functions.get(target_func_name)
        else:
            solcode_chunk = full_sol_code
        
        chunk_type = "CONTRACT_INVARIANT" if prop['type']=="INVARIANT" else "FUNCTION_RULE"
        record_id = f"{source_contract_name.replace('.sol','')}_{prop['name']}" #property wise id for source contract

        records.append({
            "id":record_id,
            "chunk_type":chunk_type,
            "source_contract":source_contract_name,
            "target_function":target_func_str,
            "text_chunk":solcode_chunk,
            "formal_property":prop['body'],
            "nl_summary":"",
            "metadata":{"rule_name":prop['name'], "rule_type":prop['type']}
        })

    return records

def main():
    if len(sys.argv) != 3:
        print("ssage: python parser.py <solidity_file_path> <spec_file_path>", file=sys.stderr)
        print("eg: python parser.py ContractsAndProperties/Auction.sol ContractsAndProperties/Auction.spec", file=sys.stderr)
        sys.exit(1)
    
    sol_path = sys.argv[1]
    spec_path = sys.argv[2]

    #path thingy
    source_contract_name = os.path.basename(sol_path)
    base_name = os.path.splitext(source_contract_name)[0]
    output_index_name = f"{base_name}_index.json"

    output_path = os.path.join(OUTPUT_DIR, output_index_name)
    full_sol_code = read_file(sol_path)
    full_spec_code = read_file(spec_path)

    if not full_sol_code or not full_spec_code:
        sys.exit(1)

    solidity_functions = parse_solidity_functions(full_sol_code)
    formal_properties = parse_cvl_properties(full_spec_code)

    index_records = create_index_records(
        solidity_functions,
        formal_properties,
        full_sol_code,
        source_contract_name
    )

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(output_path,'w') as f:
        json.dump(index_records, f, indent=4)

    print(f"Succesfully generated and saved at {output_path}")

if __name__ == "__main__":
    main()