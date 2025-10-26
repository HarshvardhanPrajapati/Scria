import os
import sys
from transformers import AutoTokenizer, AutoModel
import torch
import json
import numpy as np
import re
import chromadb

MODEL_NAME = "microsoft/codebert-base"
PATH_TO_CHROMA_DB = os.path.join(os.getcwd(), 'DataIndex', 'chroma_db')
BATCH_SIZE = 32

path_to_contract = sys.argv[1] #takes the path as input as its been called by app.js with path as CLI argument

def setup_enviornment():
    device = torch.device("cuda") if torch.cuda.is_available() else torch.device("cpu")

    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME)
    model = AutoModel.from_pretrained(MODEL_NAME).to(device)
    model.eval()

    return tokenizer,model,device

def read_contract(path):
    try:
        with open(path,'r',encoding='utf-8') as f:
            contract_data = f.read()
        return contract_data
    except Exception as e:
        print(f"error occured {e}")
        sys.exit(1)
    
def clean_code(code_chunk):
    #regex.substitute(pattern,replacement,string)
    code_chunk = re.sub(r'/\*[\s\S]*?\*/', '', code_chunk)
    code_chunk = re.sub(r'(//.*|import\s+[^;]*;|pragma\s+[^;]*;)', ' ', code_chunk) 
    code_chunk = re.sub(r'\s+', ' ', code_chunk).strip()
    return code_chunk

def generate_query_vector(tokenizer,model,device,code_chunk):
    client = chromadb.PersistentClient(path = PATH_TO_CHROMA_DB)
    collection = client.get_or_create_collection(name="scria_knowledge_base")

    text_to_embed = clean_code(code_chunk)
    input = tokenizer(
        [text_to_embed], 
        return_tensors="pt", 
        padding=True, 
        truncation=True 
    ).to(device)

    with torch.no_grad():
        model.eval()
        output = model(**input)
        query_vector = output.last_hidden_state[:, 0, :].cpu().tolist()
        
    return query_vector
    
def top_n_metadata_retrieval(code_chunk,n):
    #load model
    tokenizer,model,device = setup_enviornment()

    #generate the query vector of the code passed
    query_vector = generate_query_vector(tokenizer,model,device,code_chunk)

    #connect to database
    try:
        client = chromadb.PersistentClient(path=PATH_TO_CHROMA_DB)
        collection = client.get_collection('scria_knowledge_base')
        if(collection.count==0):
            print("collection doesnt exist, run vectorizer.py to create the collection")
            return
    except Exception as e:
        print(f"error occured: {e}")
        return
    
    #perform semantic search
    results = collection.query(
        query_embeddings=query_vector,
        n_results=n,
        include=['metadatas','distances']
    )
    return results

if __name__ == '__main__':
    code_chunk = read_contract(path_to_contract)
    similar_ones = top_n_metadata_retrieval(code_chunk,3)
    if similar_ones:
        print(json.dumps(similar_ones))
    else:
        print(json.dumps({"error": "Retrieval failed or returned empty result."}), file=sys.stderr)

    sys.stdout.flush()
