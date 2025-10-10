#!/usr/bin/env node
import { fileURLToPath } from "url";
import { GoogleGenAI } from "@google/genai";
import { spawnSync } from "child_process"; //to run the cli commands to forge test the script
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
dotenv.config({ silent: true });


//taking the command
const args = process.argv.slice(2);

let generate = false;
let property = null;

//parse flags
for (let i = 0; i < args.length; i++) {
    if (args[i] === "--gen") {
        generate = true;
    } else if (args[i] === "--property" && args[i + 1]) {
        property = args[i + 1];
        i++;
    } else if(args[i] === "--help") {
        console.log(`
Usage: $ scria [options]
            
Options:
--gen                       Generate properties
--property <file>           Solidity contract file (required)
--help                      Show this help panel
--show --vulnerabilities    Return possible vulnerabilities
--show --test-report        Return test cases report
        `);
        process.exit(0);
    } else {
        console.log(`Invalid command: ${args[i]}
Type "scria --help" for supported commands`);
            process.exit(1);
    }
}

const ai = new GoogleGenAI(process.env.GEMINI_API_KEY);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const path_to_contract = path.join(__dirname, 'src', property);
const contract_data = fs.readFileSync(path_to_contract, "utf-8");

setTimeout(() => {
    console.log("Contract loaded successfully");
}, 1000);

setTimeout(() => {
    console.log("Generating properties, might take some time");
}, 3000);

async function llm_script() {
    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: `Output only the Solidity contract (starting with // SPDX-License-Identifier: MIT). No extra text, no markdown code formatting.

Below is the smart contract
${contract_data}
Your task is to create the script for this contract, the deployement script for foundry only..
after that i'll ask you to write the tests to detect major vulnerabilities, so better keep your script acc so that it can have tests accomodated
you only have to response the deploying script, 
for importing the contract, the contract is located at src/demo_contract_staking.sol`
    });
    return response.text;
}

const script_data = await llm_script();
const script_dir = path.join(__dirname, 'script');
let script_file_name = property.substring(0,property.length - 4);
const path_to_script = path.join(script_dir,`${script_file_name}_script.s.sol`);
const writeFile = fs.writeFileSync(path_to_script,
    script_data,
    "utf-8"
);

 async function llm_tests_generator() {
    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: `
Output only the Solidity contract (starting with // SPDX-License-Identifier: MIT). No extra text, no markdown code formatting.

// Below is the smart contract to be tested, it is located at src/${property}
// ${contract_data}
And here is the script that is used to deploy the contract stored at script/${script_file_name}_script.s.sol

// For each of the following major vulnerability categories, generate a suite of property tests for Foundry:
//
// 1. Reentrancy: Test that state changes are finalized before external calls, preventing recursive withdrawals.
// 2. Access Control: Verify that only authorized addresses can call privileged functions.
// 3. Integer Overflow/Underflow: Fuzz test arithmetic operations with large and small numbers to ensure they don't wrap around.
// 4. Price Manipulation: Test that the contract's logic is not vulnerable to sudden, arbitrary price changes from a single oracle.
// 5. DoS/Resource Exhaustion: Fuzz test functions with large loops or dynamic arrays to ensure they don't exceed the block gas limit.
// 6. Timestamp Manipulation: Test that time-sensitive functions do not rely on block.timestamp.
// 7. Cross-Function/State Consistency: Test complex multi-step transactions to ensure the contract's state remains consistent.
// 8. Upgrades/Proxy Pattern Flaws: Test that storage slots and state variables are not corrupted during an upgrade.
//
// Instructions:
// - Create a single Foundry test file.
// - Import forge-std/Test.sol and the contract being tested.
// - Use a setUp() function to deploy a new instance of the contract before each test.
// - For Fuzz tests, use a uint256 parameter in the function signature. For non-fuzz tests, you may use a vm.prank and vm.deal to set up specific test conditions.
// - Ensure all tests include require statements to check for expected conditions or vm.expectRevert for negative scenarios.
// - Functions must be internal or public to be callable within the test contract. Do not make them external.
// - The output should be a single, compilable Solidity file with 5-15 tests. Each test should target a realistic exploit scenario for the specified vulnerability categories. The code should be clean, error-free, and directly usable in a Foundry project.
        `,
    });
    return response.text;
}

const test_data = await llm_tests_generator();
const test_dir = path.join(__dirname,'test');
let test_file_name = property.substring(0, property.length - 4);
const path_to_test = path.join(test_dir, `${test_file_name}.t.sol`);
const writeTestFile = fs.writeFileSync(path_to_test,
    test_data,
    "utf-8"
);