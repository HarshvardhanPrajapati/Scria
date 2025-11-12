#!/usr/bin/env node
import { fileURLToPath } from "url";
import { ComputeTokensResponse, GoogleGenAI } from "@google/genai";
import { spawnSync } from "child_process"; //needed for running the python script as child process
import fs, { read } from "fs";
import path from "path";
import dotenv from "dotenv";
import { error } from "console";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

//configs
dotenv.config({ silent: true });
const PYTHON_SCRIPT_PATH = path.join(__dirname, 'scripts', 'rag_agent.py');
const CVL_GENERATION_CONTENTS_PATH = path.join(__dirname, 'prompts', 'CVL_generation_contents.txt');
const CVL_GENERATION_SYSTEM_INSTRUCTION_PATH = path.join(__dirname, 'prompts', 'CVL_generation_systemInstruction.txt');

//defining colours for terminal output
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const GREEN = '\x1b[32m';
const BOLD = '\x1b[1m';
const RESET = '\x1b[0m';

// variables, clients, instances
const args = process.argv.slice(2);
let generate = false;
let property = null;
const ai = new GoogleGenAI(process.env.GEMINI_API_KEY);
let intent = null;

//taking input from CLI
for (let i = 0; i < args.length; i++) {
    if (args[i] === "--gen") {
        generate = true;
    } else if (args[i] === "--property" && args[i + 1]) {
        property = args[i + 1];
        i++;
    } else if (args[i] === "--help") {
        console.log(`
Usage: $ scria [options]
            
Options:
--gen                       Generate properties
--property <file>           Solidity contract file (required)
--help                      Show this help panel
--show --vulnerabilities    Return possible vulnerabilities
--show --test-report        Return test cases report
        `);
        process.exit(1);
    } else {
        console.log(`Invalid command: ${args[i]}
Type "scria --help" for supported commands`);
        process.exit(1);
    }
}


//to read prompts from the given path
async function readPrompts(path_to_prompt) {
    let prompt = fs.readFileSync(path_to_prompt, "utf-8");
    return prompt;
}

//core LLM augmentation function
async function CVL_generation(retrieved_templates, user_plain_english_intent, N) {
    const CVL_generation_contents = await readPrompts(CVL_GENERATION_CONTENTS_PATH);
    const CVL_generation_systemInstruction = await readPrompts(CVL_GENERATION_SYSTEM_INSTRUCTION_PATH);

    const context_templates_string = retrieved_templates.map((template,index) => {
        return `--- TEMPLATE ${index + 1} (${template.rule_type} for ${template.target_function}) ---\n${template.formal_property}\n`;
    })
    .join('\n');

    const final_contents = CVL_generation_contents
        .replace('{user_plain_english_intent}', user_plain_english_intent)
        .replace('{context_templates}', context_templates_string);

    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        config: {
            systemInstruction: CVL_generation_systemInstruction,
        },
        contents: final_contents
    });
    return response.text;
}

async function main() {
    //loading contract data and paths
    const path_to_contract = path.join(__dirname, 'src', property);
    const contract_data = fs.readFileSync(path_to_contract, "utf-8");
    const base_file_name = path.parse(property).name;

    //wont allow contracts with more than 100 lines of code
    const lines = contract_data.split('\n');
    const numberOflines = lines.length;
    if (numberOflines > 100) {
        console.log(RED + "Contract exceeds the limit size (100 lines)" + RESET);
        process.exit(1);
    }

    //moving ahead, we have loaded the contract
    console.log(GREEN + BOLD + "Contract loaded successfully" + RESET);

    //sending the contract to python for vectorization and retrieving N most common contracts and mapped properties
    const python_process = spawnSync('python', ['scripts/rag_agent.py', path_to_contract], { encoding: 'utf-8' });
    const python_output = python_process.stdout.trim();
    let retrieved_templates_result;
    try {
        retrieved_templates_result = JSON.parse(python_output)
    } catch(e) {
        console.error(RED + "\nFailed to parse RAG results from Python. Received non-JSON output." + RESET);
        console.error(RED + `Raw Python Output: ${python_output.substring(0, 100)}...` + RESET);
        process.exit(1);
    }

    let retrieved_templates = retrieved_templates_result.metadatas[0];
    console.log(retrieved_templates);

    intent = "If passed empty token and burn amount arrays, burnBatch must not change token balances or address permissions.";
    const final_CVL_code = await CVL_generation(retrieved_templates, intent, 3);
    console.log(final_CVL_code);
}

main().catch(console.error);
