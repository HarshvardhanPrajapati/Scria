#!/usr/bin/env node
import { fileURLToPath } from "url";
import { ComputeTokensResponse, GoogleGenAI } from "@google/genai";
import { spawnSync } from "child_process"; //needed for running the python script as child process
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { error } from "console";
dotenv.config({ silent: true });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

//defining colours for terminal output
const RED = '\x1b[31m';
const YELLOW = '\x1b[33m';
const GREEN = '\x1b[32m';
const BOLD = '\x1b[1m';
const RESET = '\x1b[0m';

// taking the command
const args = process.argv.slice(2);

let generate = false;
let property = null;

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
}

main().catch(console.error);
