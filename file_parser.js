#!/usr/bin/env node
import { fileURLToPath } from "url";
import { ComputeTokensResponse, GoogleGenAI } from "@google/genai";
import { spawnSync } from "child_process";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { error } from "console";
dotenv.config({ silent: true });

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


// parsing the terminal command
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
    process.exit(0);
  } else {
    console.log(`Invalid command: ${args[i]}
Type "scria --help" for supported commands`);
    process.exit(1);
  }
}


//creating the instance for the AI model
const ai = new GoogleGenAI(process.env.GEMINI_API_KEY);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function main() {

  //loading contract data and paths
  const path_to_contract = path.join(__dirname, 'src', property);
  const contract_data = fs.readFileSync(path_to_contract, "utf-8");
  const base_file_name = path.parse(property).name;
  const lines = contract_data.split('\n');
  const numberOflines = lines.length;
  if(numberOflines > 100){
    console.log(RED + "Contract exceeds the limit size (100 lines)" + RESET);
    process.exit(1);
  }


  console.log(GREEN + BOLD + "Contract loaded successfully" + RESET);
  console.log("Generating Script");

  //function for generating script
  async function llm_script() {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: `Output only the Solidity contract (starting with // SPDX-License-Identifier: MIT). No extra text, no markdown code formatting.

Below is the smart contract
${contract_data}
Your task is to create the script for this contract, the deployement script for foundry only..
after that i'll ask you to write the tests to detect major vulnerabilities, so better keep your script acc so that it can have tests accomodated
you only have to response the deploying script, 
for importing the contract, the contract is located at src/${property}`
    });
    return response.text;
  }

  //writing the script
  const script_data = await llm_script();
  const script_dir = path.join(__dirname, 'script');
  const path_to_script = path.join(script_dir, `${base_file_name}_script.s.sol`);
  fs.writeFileSync(path_to_script, script_data, "utf-8");

  console.log("Generating Tests, might take some time");


  //function for generating tests
  async function llm_tests_generator() {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: `
Write a Foundry test contract for the provided smart contract. The test contract must be named ${base_file_name}Test and inherit from Test (forge-std).

Requirements:
- The test contract must be simple, clear, and focused on the most critical vulnerabilities.
- Write 5-10 tests that cover the following vulnerability categories: 
  1. Reentrancy
  2. Access Control
  3. Integer Overflow/Underflow
  4. Price Manipulation
  5. DoS/Resource Exhaustion
  6. Timestamp Manipulation
  7. Cross-Function/State Consistency
- However, if a category is not applicable to the contract, skip it and focus on the applicable ones.

Instructions:
- Import forge-std/Test.sol and the contract to test (src/${property}).
- Use a setUp() function to deploy the contract.
- For fuzz tests, use uint256 parameters and use vm.assume to bound inputs when necessary to avoid excessive gas.
- Use vm.prank and vm.deal for setting up msg.sender and balance.
- Use require for assertions and vm.expectRevert for expected failures.
- Make sure all test functions are public.
- Handle public mapping getters by unpacking the tuple if the mapping returns a struct.

Output only the Solidity code for the test contract, starting with the SPDX license identifier. Do not include any extra text or markdown formatting.

The contract to test is located at src/${property} and the code is:

${contract_data}
        `,
    });
    return response.text;
  }

  //function for resolving errors in test
  async function llm_error_resolver(error_that_occured) {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: `
Here is the contract:
${contract_data}

And here is the error that occured during its execution, this means there can be more errors then this, i want you to solve and remove every single possible error in this contract
here is the current error
${error_that_occured}

here is the path to the contract src/${property}

Output only the Solidity code for the test contract, starting with the SPDX license identifier. Do not include any extra text or markdown formatting.
Also dont start the output with \`\`\` and end with this..the first thing in your response should only be SPDX-
`,
    });
    return response.text;
  }

  //writing the tests
  const test_data = await llm_tests_generator();
  const test_dir = path.join(__dirname, 'test');
  const path_to_test = path.join(test_dir, `${base_file_name}.t.sol`);
  fs.writeFileSync(path_to_test, test_data, "utf-8");

  console.log("Compiling Tests");


  //iterating to resolved errors, trying to compile
  for (let i = 0; i < 3; i++) {
    const compileResult = spawnSync('forge', ['compile'], { stdio: 'pipe' });
    if (compileResult.status !== 0) {
      console.error(RED + "Compilation failed"+ RESET);
      console.log("Updating tests and rerunning the pipeline");
      const updated_tests = await llm_error_resolver(compileResult.stderr.toString());
      //console.log(compileResult.stderr.toString());
      fs.writeFileSync(path_to_test, updated_tests, "utf-8");
    }
  }

  console.log(GREEN + "Compilation successful, running tests" + RESET);

  //running tests
  const relative_path_to_test = path.join('test', `${base_file_name}.t.sol`);
  const testResult = spawnSync('forge', ['test', '--match-path', relative_path_to_test], { stdio: 'pipe' });
  const testOutput = testResult.stdout.toString() + testResult.stderr.toString();
  if(testResult.stderr.toString() == "") {
    console.log(GREEN + "No significant vulnerability detected" + RESET);
    process
  }

  //function to analyze vulnerabilites
  async function llm_vulnerability_analyzer(test_output, test_data) {
    const response = await ai.models.generateContent({
      model: "gemini-2.5-flash",
      contents: `
You are a smart contract security expert. Your task is to analyze a smart contract and its Foundry test results to identify and report vulnerabilities.

Provide your response in a structured format as a list of findings. For each finding, list only the function name and the potential vulnerability. Do not include any extra text, descriptions, or explanations.

The output must follow this exact format:

- **Function Name:** [Vulnerability]

Here are the contract and test details:

Test File:
\`\`\`solidity
${test_data}
\`\`\`

Terminal Output:
\`\`\`
${test_output}
\`\`\`

you dont have to give vulnerability in each contract, jus the ones serious ones you see in the terminal output...i dont want you to write ** before and after the function name
i only want you to like yk jus the ones serious one you see are failing tests in the terminal output...nothing except that only the failing tests in the terminal
also you dont have to wrtite silly vulnerabilities like error handling or smth...only the vunearbilities that can be exploited
`
    });
    return response.text;
  }

  //printing vulnerability report
  const vulnerabilityReport = await llm_vulnerability_analyzer(testOutput, test_data);
  console.log(RED + BOLD + "\n--- Potential Vulnerabilites ---" + RESET);
  console.log(vulnerabilityReport);
}

main().catch(console.error);