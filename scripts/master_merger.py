import sys
import os
import json
import glob

master_list = []
INPUT_DIR = os.path.join(os.getcwd(),'DataIndex','raw_index')

search_pattern = os.path.join(INPUT_DIR, '*.json')
all_index_files = glob.glob(search_pattern)

#would have to read all individual indexes from raw_index
def read_file(filepath):
    try:
        with open(filepath,'r',encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        print("File doesnt exist")
        return None
    except json.JSONDecodeError:
        print(f"Error reading JSON file at {filepath}", file = sys.stderr)
        return None
    except Exception as e:
        print(f"Error occured during searching of file at {filepath}; {e}", file=sys.stderr)
        return None

for _filepath in all_index_files:
    try:
        file_data = read_file(_filepath)
        if file_data is not None:
            master_list.extend(file_data)
    except Exception as e:
        print(f"Error occurred reading file at {_filepath}; {e}", file=sys.stderr)

master_index_path = os.path.join(os.getcwd(), 'DataIndex', 'master_index.json')
try:
    os.makedirs(os.path.dirname(master_index_path), exist_ok=True)
    with open(master_index_path,'w') as f:
        json.dump(master_list,f,indent=4)
except Exception as e:
    print("failed to write the master file")
    sys.exit(1)