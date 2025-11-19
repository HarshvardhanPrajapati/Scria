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
async function CVL_generation(retrieved_templates, user_plain_english_intent, contract_code, function_list, state_vars) {
    const CVL_generation_contents = await readPrompts(CVL_GENERATION_CONTENTS_PATH);
    const CVL_generation_systemInstruction = await readPrompts(CVL_GENERATION_SYSTEM_INSTRUCTION_PATH);

    const contextTemplatesString = retrieved_templates.map((template, index) => {
        return `--- TEMPLATE ${index + 1} (${template.rule_type} for ${template.target_function}) ---\n${template.formal_property}\n`;
    }).join('\n');

    const symbolsContext = `
Functions in contract: ${function_list.join(', ')}\n
State variables: ${state_vars.join(', ')}\n\n
Please use only these identifiers in your CVL property generation.\n
`;

    const fullPrompt = CVL_generation_contents.replace('{user_plain_english_intent}', user_plain_english_intent)
        .replace('{context_templates}', contextTemplatesString)
        + symbolsContext;

    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        config: {
            systemInstruction: CVL_generation_systemInstruction,
        },
        contents: fullPrompt
    });
    return response.text;
}

//function to extract solidity identifiers
function extractSolidityIdentifiers(contractCode) {
    const regex = /\b[a-zA-Z_][a-zA-Z0-9_]*\b/g;
    const identifiers = new Set();
    let match;
    while ((match = regex.exec(contractCode)) !== null) {
        identifiers.add(match[0]);
    }
    return identifiers;
}

//to validate the returned CVL property from LLM call
function validateCVLProperty(propertyText, contractIdentifiers) {
    //const ruleMatches = propertyText.match(/rule\s+\w+\s*\{/g) || [];
    const ruleMatches = propertyText.match(/rule\s+\w+(\([^)]*\))?\s*\{/g) || [];

    if (ruleMatches.length !== 1) {
        return { valid: false, error: "Output must contain exactly one 'rule' block." };
    }

    const ruleNameMatch = propertyText.match(/rule\s+(\w+)\s*\{/);
    const ruleName = ruleNameMatch ? ruleNameMatch[1] : null;

    const openBraces = (propertyText.match(/{/g) || []).length;
    const closeBraces = (propertyText.match(/}/g) || []).length;
    if (openBraces !== closeBraces) {
        return { valid: false, error: "Unbalanced braces in the generated property." };
    }

    let declared_locals = new Set(); //all locally declared variables etc so to keep track of them when validating
    
    //to identify the parameteres passed with the fucntion, as these wont be declared in function body, if not extracted from the parameter list, they would throw unidentified variable error
    const param_match = propertyText.match(/rule\s+\w+\s*\(([^)]*)\)/);
    if (param_match && param_match[1].trim().length > 0){
        const params = param_match[1].split(',').map(s=> s.trim());
        for (const param of params) {
            const parts = param.split(/\s+/);
            const var_name = parts[parts.length - 1];
            declared_locals.add(var_name);
        }
    }

    //all lcoally declared vars
    const localDeclRegex = /\b(?:bool|uint256|uint|int|address|string|bytes|env|method)\s+([a-zA-Z_][a-zA-Z0-9_]*)\b/g;
    let match;
    while((match = localDeclRegex.exec(propertyText)) !== null){
        declared_locals.add(match[1]);
    }

    const token_regex = /\b[a-zA-Z_][a-zA-Z0-9_]*\b/g;
    const tokens = propertyText.match(token_regex) || [];

    const allowedKeywords = new Set([
        'rule', 'true', 'false', 'require', 'assert', 'invariant', 'pre', 'post',
        'env', 'e', 'method', 'call', 'returns', 'revert', 'old', 'if', 'else',
        'for', 'while', 'break', 'continue', 'return', 'bool', 'uint256', 'uint',
        'int', 'address', 'string', 'bytes', 'env', 'function'
    ]);

    //check tokens
    for (const token of tokens) {
        //skip rule name from validation
        if(
            token === ruleName || 
            declared_locals.has(token) ||
            allowedKeywords.has(token)
        ) {
            continue;
        }

        if(!contractIdentifiers.has(token)){
            return { valid: false, error: `Reference to undefined identifier '${token}'.` };
        }
    }
    return { valid: true };
}

//regenerate the property tht has error, for maxm 3 times
async function generatePropertyWithRevision(retrievedTemplates, userIntent, contractCode, functionList, stateVars, maxRetries = 3) {
    const contractIdentifiers = extractSolidityIdentifiers(contractCode);
    let lastError = "";
    let lastOutput = "";

    for (let attempt = 1; attempt <= maxRetries; attempt++) {
        let promptIntent = userIntent;
        if (lastError) {
            promptIntent += `\n\nThe previously generated property was:\n${lastOutput}\n\nPlease fix the following errors from this output:\n${lastError}`;
        }

        lastOutput = await CVL_generation(retrievedTemplates, userIntent, contractCode, functionList, stateVars);

        const validationResult = validateCVLProperty(lastOutput, contractIdentifiers);
        if (validationResult.valid) {
            console.log(GREEN + BOLD + `Property generation successful at attempt ${attempt}.` + RESET);
            return lastOutput;
        } else {
            lastError = validationResult.error;
            console.log(RED + `Validation failed at attempt ${attempt}: ${lastError}\nRetrying...` + RESET);
        }
    }

    throw new Error(`Failed to generate valid property after ${maxRetries} attempts.\nLast Output:\n${lastOutput}`);
}

//function to run the parser.py for the contract n property, will create the json data with function names list, state vars etc info tot the DataIndex/raw_data
async function runParserPy(solidityPath, specPath) {
    const resolvedPythonPath = path.join(__dirname, 'scripts', 'parser.py');
    const result = spawnSync('python', [resolvedPythonPath, solidityPath, specPath], { encoding: 'utf-8' });

    if (result.error) {
        throw result.error;
    }

if (result.status !== 0) {
    console.error("parser.py exited with non-zero status code:", result.status);
    if (result.stdout) {
        console.error("parser.py stdout:\n", result.stdout);
    }
    if (result.stderr) {
        console.error("parser.py stderr:\n", result.stderr);
    }
    if (result.error) {
        console.error("Error object:", result.error);
    }
    throw new Error(`parser.py failed with exit code ${result.status}`);
}

    const outputPath =  path.join(__dirname, 'DataIndex', 'raw_index', path.basename(solidityPath, '.sol') + '_index.json');
    if (!fs.existsSync(outputPath)) {
        throw new Error("Parser output not found at " + outputPath);
    }

    const jsonData = JSON.parse(fs.readFileSync(outputPath, 'utf-8'));
    return jsonData;
}

//to retrieve the imp items from teh parser.py output
async function extractSymbolFromParserOutput(jsonData) {
    const contractContext = jsonData.find(rec => rec.chunk_type === "CONTRACT_CONTEXT");
    const functionList = contractContext?.metadata?.function_list || [];
    const stateVars = contractContext?.metadata?.state_variables || [];
    return { functionList, stateVars };
}

async function main() {
    //loading contract data and paths
    const path_to_contract = path.join(__dirname, 'src', property);
    const contract_data = fs.readFileSync(path_to_contract, "utf-8");
    const base_file_name = path.parse(property).name;
    const path_to_spec = path.join(__dirname, 'src', base_file_name + '.spec');

    //wont allow contracts with more than 100 lines of code
    const lines = contract_data.split('\n');
    const numberOflines = lines.length;
    if (numberOflines > 100) {
        console.log(RED + "Contract exceeds the limit size (100 lines)" + RESET);
        process.exit(1);
    }

    //moving ahead, we have loaded the contract
    console.log(GREEN + BOLD + "Contract loaded successfully" + RESET);

    //running parser.py to get the indexed data
    let parser_output;
    try{
        parser_output = await runParserPy(path_to_contract, path_to_spec);
    } catch(err) {
        console.error(RED + `error running parser.py: ${err.message}` + RESET);
        process.exit(1);
    }

    //need to extract the functions and state variables from the user input contract, using parser.py
    const {functionList: function_list, stateVars: state_vars} = await extractSymbolFromParserOutput(parser_output);
    
    console.log(function_list);
    //sending the contract to python for vectorization and retrieving N most common contracts and mapped properties
    const python_process = spawnSync('python', ['scripts/rag_agent.py', path_to_contract], { encoding: 'utf-8' });
    const python_output = python_process.stdout.trim();

    let retrieved_templates_result;
    try {
        retrieved_templates_result = JSON.parse(python_output)
    } catch (e) {
        console.error(RED + "\nFailed to parse RAG results from Python. Received non-JSON output." + RESET);
        process.exit(1);
    }

    //processing the received metadata
    let retrieved_templates = retrieved_templates_result.metadatas ? retrieved_templates_result.metadatas[0] : [];
    if (!retrieved_templates || retrieved_templates.length === 0) {
        console.error(RED + "no templates retrieved from RAG" + RESET)
    }
    //console.log(retrieved_templates);

    intent = "The transfer function must never allow sending tokens more than the sender's current balance.";

    const final_CVL_code = await generatePropertyWithRevision(retrieved_templates, intent, contract_data, function_list, state_vars);
    console.log(GREEN + BOLD + "\n --- generated CVL propty ---" + RESET)
    console.log(final_CVL_code);
}

main().catch(e => {
    console.error(e);
    process.exit(1);
})
