import os
import sys
import json
import subprocess
from collections import defaultdict

#config
PATH_TO_FOLDER = "ContractsAndProperties"
PARSER_SCRIPT = "parser.py"

def create_raw_indices():
    file_groups = defaultdict(dict)
    if not os.path.isdir(PATH_TO_FOLDER):
        print("ContractAndProperties folder cannot be found")
        sys.exit(1)
    for filename in os.listdir(PATH_TO_FOLDER): #creating a dict of all files in ContractsAndProperties
        base_name, ext = os.path.splitext(filename)
        if ext in ['.sol','.spec']:
            file_groups[base_name][ext]=filename
    
    processed_count = 0 #count for total files succesfully parsed
    total_count = len(file_groups)

    for base_name, files in file_groups.items(): #running parser for each pair of .sol and .spec
        sol_file = files.get('.sol')
        spec_file = files.get('.spec')
        if sol_file and spec_file:
            sol_path = os.path.join(PATH_TO_FOLDER,sol_file)
            spec_path = os.path.join(PATH_TO_FOLDER,spec_file)
            command = ['python','scripts/'+PARSER_SCRIPT,sol_path,spec_path]

            try:
                result = subprocess.run(
                    command,
                    capture_output=True,
                    text = True,
                    check= True
                )
                print(f"success: {result.stdout.strip()}")
                processed_count+=1
            
            except subprocess.CalledProcessError as e:
                print(f"parser failed for {base_name}.",file=sys.stderr)
                print(e)
            except Exception as e:
                print(f"error occured")
                print(e)
                sys.exit(1)
            
        else:
            missing_file = '.spec' if sol_file else '.sol'
            print(f"skipping {base_name}, missing {missing_file} file", file=sys.stderr)

    print(f"total pairs processed:{processed_count} out of {total_count}")

if __name__ == '__main__':
    create_raw_indices()
