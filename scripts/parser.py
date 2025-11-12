import re #regular expression
import json
import os
import sys
import hashlib
from typing import Set, List, Dict

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
    
#core solidity parsing logic, returns function in dict form
def parse_solidity_functions(path_to_sol_file):
    with open(path_to_sol_file,"r",encoding="utf-8") as f:
        line_wise_code = f.readlines() #needed line wise to extract function body, also diff fnc with same name would be treated as diff functions as they all wouldh have diff line numbers    
    code = "".join(line_wise_code)
    functions = {}

    #function_pattern = r'function\s+([a-zA-Z0-9_]+)\s*\(.*?\).*?\{.*?\}' #function regular expression
    function_pattern = re.compile(r"function\s+(\w+)[\s\S]*?\{", re.DOTALL)

    for match in function_pattern.finditer(code):
        function_name = match.group(1)
        start_line = code[:match.start()].count("\n")+1

        open_brackets = 1
        end_line_index = match.end()
        while end_line_index<len(code) and open_brackets>0: #match brackets, so to avoid nested brackets inside the function
            if code[end_line_index] == '{':
                open_brackets+=1
            elif code[end_line_index] == '}':
                open_brackets-=1
            end_line_index+=1

        end_line = code[:end_line_index].count("\n")+1
        function_body = line_wise_code[start_line-1 : end_line]

        functions[function_name] = (function_name, start_line, end_line, function_body)
    
    if not functions:
        print("no function found in {path_to_sol_file}")
    
    return functions

#find all methods names in the spec file. filter out require/assert properly
def find_methods(file_path):
    if not os.path.exists(file_path):
        print(f"cant file at path: {file_path}")
        return []

    with open(file_path, "r", encoding="utf-8") as f:
        code = f.read()
    
    methods_block_pattern = re.compile(r"methods\s*\{[\s\S]*?\}", re.DOTALL)
    method_name_pattern = re.compile(r"^\s*([a-zA-Z0-9_\.]+)\(", re.MULTILINE)

    methods_match = methods_block_pattern.search(code)
    methods = []
    new_methods = []

    if methods_match:
        methods_block = methods_match.group()
        methods = method_name_pattern.findall(methods_block)
        new_methods = [method for method in methods if method not in ['require','assert']]

    return new_methods

#parsing them CVL properties, creating the properties record
def find_code_blocks(path_to_spec_file):
    patterns = {
        "invariant": re.compile(r"invariant\s+(\w+)[\s\S]*?\{", re.DOTALL),
        "rule": re.compile(r"rule\s+(\w+)[\s\S]*?\{", re.DOTALL)
    }
    
    properties = [] #list of dictionaries
    methods = find_methods(path_to_spec_file)

    if not os.path.exists(path_to_spec_file):
        print(f"spec file does not exist at {path_to_spec_file}")
        return properties

    with open(path_to_spec_file, "r", encoding="utf-8") as f:
        contract_lines = f.readlines()

    code = "".join(contract_lines)

    for block_type,pattern in patterns.items():
        for match in pattern.finditer(code):
            block_name = match.group(1)
            start_line = code[:match.start()].count("\n")+1
            open_brackets = 1
            end_line_index = match.end()
            while end_line_index < len(code) and open_brackets>0:
                if code[end_line_index]=="{":
                    open_brackets+=1
                elif code[end_line_index]=="}":
                    open_brackets-=1
                end_line_index+=1
            
            end_line = code[:end_line_index].count("\n")+1
            block_content = contract_lines[start_line-1: end_line]
            block_content_str = "".join(block_content)

            methods_in_block = [method for method in methods if method in block_content_str]

            properties.append({
                'file_path': path_to_spec_file,
                'block_type':block_type,
                'block_name':block_name,
                'start_line':start_line,
                'end_line':end_line,
                'block_content':block_content,
                'methods_in_block':methods_in_block
            })
    
    if not properties:
        print(f"no code blocks found in {path_to_spec_file}")
    
    return properties

#function to extract all state vars in solidity code, imp to monitor the state of contract
def extract_state_variables(path_to_sol_file):
    with open(path_to_sol_file, "r", encoding='utf-8') as f:
        contract_lines = f.readlines()
    
    sol_code = "".join(contract_lines)

    state_vars = set()

    patterns = [
        r'(?:public|private|internal|external)\s+(\w+)\s*;',
        r'(?:uint|int|bool|address|string|bytes)\d*\s+(?:public|private|internal)?\s*(\w+)\s*;',
        r'mapping\s*\([^)]+\)\s+(?:public|private|internal)?\s*(\w+)\s*;'
    ]

    for pattern in patterns:
        matches = re.findall(pattern, sol_code)
        state_vars.update(matches)
    
    return state_vars

#check if the function has any state variable assignment, we need this as we only wanna keep properties that verify functions that modify state variables. i.e. not just getter functions but functions that are actually changing state on the chain
def check_state_var_assignment(function_body: str, state_vars: Set[str]):
    nodes = function_body.split(';')

    for node in nodes:
        if '=' in node:
            left_side = node.split('=')[0].strip()
            for var in state_vars:
                if re.search(r'\b' + re.escape(var) + r'\b', left_side):
                    return True
            
    return False

#CVL methods having function calls (that changes states) might need human review, as these methods are changing states
def has_function_calls(function_body):
    if "view" in str(function_body).lower():
        return False
    
    #extract content between {...}
    match = re.search(r'\{(.*)\}', str(function_body), re.DOTALL)
    if not match:
        return False
    
    inner_body = match.group(1)

    #re to find method calls
    method_call_pattern = re.compile(r'\.\s*(\w+)\s*\(')
    method_calls = method_call_pattern.findall(inner_body)

    if not method_calls: #no method called..
        return False
    
    #check if they are read fnc like 'balaceOf' or 'totalsupply'
    allowed_methods = {'balanceOf', 'totalSupply'}
    for method_name in method_calls:
        if method_name not in allowed_methods:
            return True #found a state changing method call
    
    return False

#make each block self-contained by expanding it to include all non-duplicate lines of fnc it references
def update_blocks_with_cross_reference(code_blocks:List[dict]):
    def find_block_by_name(name):
        for block in code_blocks:
            if block['block_name'] == name:
                return block
        return None
    
    def update_block_content(block, visited=None):
        if visited is None:
            visited = set()
        
        if block['block_name'] in visited:
            return []
    
        visited.add(block['block_name']) #maintain a visited to know what codes are already being included...do this to avoid duplicacy
        updated_content = []

        for line in block['block_content']:
            if line not in updated_content:
                updated_content.append(line)
            
            for other_block in code_blocks:
                if other_block['block_name'] in line and other_block['block_name'] != block['block_name']:
                    referenced_block = find_block_by_name(other_block['block_name'])
                    if referenced_block:
                        ref_block_content = update_block_content(referenced_block, visited)
                        for ref_line in ref_block_content:
                            if ref_line not in updated_content:
                                updated_content.append(ref_line)
        
        return updated_content
    
    for block in code_blocks:
        block['block_content'] = update_block_content(block)

#to generate unique hash for each code block
def generate_block_hash(block:dict):
    block_content_string = str(block)
    return hashlib.md5(block_content_string.encode()).hexdigest()

#function to link CVL property to its target function, VERY IMP, returns set of target functions linked to that property
def determine_target_function(prop_body, all_solidity_functions, methods_in_block):
    target_fncs = set()
    body_lower = prop_body.lower()
    
    #check for methods in the methods block
    for method in methods_in_block:
        clean_method = method.split('.')[-1]
        if clean_method in all_solidity_functions:
            target_fncs.add(clean_method)

    #also check for direct func refernces in the property body
    for func_name in all_solidity_functions.keys():
        func_lower = func_name.lower()
        if f"{func_lower}(" in body_lower or f"{func_lower}@" in body_lower:
            target_fncs.add(func_name)
        
    #make invariant global if no specifix fnc is called, cuz invariant holds true for any function
    if not target_fncs and "invariant" in body_lower:
        return "ALL"
    
    return "/".join(sorted(list(target_fncs))) or "UNKNOWN"

#actually creating the JSONs that we wil be storing in our vector database, also tracking state vars
def create_index_records(solidity_functions, formal_properties, full_sol_code, source_contract_name, state_vars):
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
        "metadata": {
            "function_list":list(solidity_functions.keys()),
            "state_variables":list(state_vars),
            "is_standard":"UNKNOWN"}
    })

    #property specific data
    for prop in formal_properties:
        target_func_str = determine_target_function("".join(prop['block_content']), solidity_functions, prop['methods_in_block'])
        solcode_chunk = ""
        target_func_names = target_func_str.split('/')

        if target_func_str in ["ALL","UNKNOWN"]: #i.e. its an invariant
            solcode_chunk = full_sol_code
        else:
            #combine related function bodies
            func_bodies = []
            for func_name in target_func_names:
                if func_name in solidity_functions:
                    func_bodies.append("".join(solidity_functions[func_name][3]))
            solcode_chunk = "\n\n".join(func_bodies) if func_bodies else full_sol_code

        #determine if state variables are modified
        modifies_state = False
        for func_name in target_func_names:
            if func_name in solidity_functions:
                func_body = "".join(solidity_functions[func_name][3])
                if check_state_var_assignment(func_body, state_vars) or has_function_calls(func_body):
                    modifies_state = True
                    break
        
        chunk_type = "CONTRACT_INVARIANT" if prop['block_type']=="invariant" else "FUNCTION_RULE"
        block_hash = generate_block_hash(prop)
        record_id = f"{source_contract_name.replace('.sol','')}_{prop['block_name']}_{block_hash[:8]}" #property n unique hash wise id for source contract

        records.append({
            "id":record_id,
            "chunk_type":chunk_type,
            "source_contract":source_contract_name,
            "target_function":target_func_str,
            "text_chunk":solcode_chunk,
            "formal_property": "".join(prop['block_content']),
            "nl_summary":"",
            "metadata":{
                "rule_name":prop['block_name'],
                "rule_type":prop['block_type'],
                "modifies_state":modifies_state,
                "methods_in_block": prop['methods_in_block'],
                "start_line": prop['start_line'],
                "end_line": prop['end_line'],
                "block_hash": block_hash
                }
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
        print("failed to read input files")
        sys.exit(1)

    solidity_functions = parse_solidity_functions(sol_path)
    formal_properties = find_code_blocks(spec_path)

    #expand proeprties with cross ref
    update_blocks_with_cross_reference(formal_properties)

    #extract state vars
    state_vars = extract_state_variables(sol_path)

    #create index recs
    index_records = create_index_records(
        solidity_functions,
        formal_properties,
        full_sol_code,
        source_contract_name,
        state_vars
    )

    #save to file
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(output_path,'w') as f:
        json.dump(index_records, f, indent=4, ensure_ascii=False)

    print(f"Succesfully generated and saved at {output_path}")

if __name__ == "__main__":
    main()