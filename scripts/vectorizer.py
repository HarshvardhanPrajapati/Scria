#this script is our AI Engine builder 

import torch
from transformers import AutoTokenizer, AutoModel
import sys
import os
import chromadb
import json
import re
import numpy as np

MODEL_NAME = "microsoft/codebert-base"
PATH_TO_MASTER_INDEX = os.path.join(os.getcwd(), 'DataIndex','master_index.json')
PATH_TO_CHROMA_DB = os.path.join(os.getcwd(), 'DataIndex', 'chroma_db')
BATCH_SIZE = 32

def setup_enviornment():
    device = torch.device("cuda") if torch.cuda.is_available() else torch.device("cpu")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModel.from_pretrained(MODEL_NAME).to(device)
    model.eval()

    return tokenizer,model,device

#fnc to discard non formal_property containing data and sanity checks and then return the data
def load_and_filter_data():
    try:
        with open(PATH_TO_MASTER_INDEX,'r',encoding='utf-8') as f:
            data = json.load(f)
            filtered_data = [record for record in data if record.get('formal_property') is not None and record.get('metadata',{}).get('rule_name') != 'sanity'] #ensures that we dont process data that doesnt provide any info abt formal_prop
            return filtered_data
    except FileNotFoundError:
        print("master_index file doesnt exist, run master_merger.py to create one")
        sys.exit(1)
    except json.JSONDecodeError:
        print("error decoding master_index.json")
        sys.exit(1)

#fnc to clean whitespaces, imports, license etc
def clean_code(code_chunk):
    #regex.substitute(pattern,replacement,string)
    code_chunk = re.sub(r'/\*[\s\S]*?\*/', '', code_chunk)
    code_chunk = re.sub(r'(//.*|import\s+[^;]*;|pragma\s+[^;]*;)', ' ', code_chunk) 
    code_chunk = re.sub(r'\s+', ' ', code_chunk).strip()
    return code_chunk

def vectorization_pipeline(tokenizer,model,device,data):
    client = chromadb.PersistentClient(path = PATH_TO_CHROMA_DB)
    collection = client.get_or_create_collection(name="scria_knowledge_base")

    for i in range(0,len(data),BATCH_SIZE):
        batch = data[i:i+BATCH_SIZE]
        texts_to_embed = [clean_code(temp_data['text_chunk']) for temp_data in batch]
        inputs = tokenizer(
            texts_to_embed, 
            return_tensors="pt", 
            padding=True, 
            truncation=True 
        ).to(device)

        with torch.no_grad():
            outputs = model(**inputs)
            embeddings = outputs.last_hidden_state[:, 0, :].cpu().tolist()
    
        metadata_list = []
        ids_list = []
        for record in batch:
            ids_list.append(record['id'])
            metadata_list.append({
                "source_contract": record['source_contract'],
                "target_function": record['target_function'],
                "formal_property": record['formal_property'],
                "rule_type": record.get('metadata',{}).get('rule_type','RULE/INV')
            })
    
    #ingesting data to our vector database
        collection.add(
            embeddings=embeddings,
            documents=[f"Rule: {m['rule_type']} for {m['target_function']}" for m in metadata_list],
            metadatas=metadata_list,
            ids=ids_list
        )

if __name__ == "__main__":
    import torch
    import re

    tokenizer,model,device = setup_enviornment()
    data = load_and_filter_data()
    vectorization_pipeline(tokenizer,model,device,data)

