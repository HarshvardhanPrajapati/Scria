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

async function llm_script_generator() {
    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: `You are an elite smart contract security auditor. Generate comprehensive vulnerability-focused properties for this Solidity contract as Foundry tests.
        You only have to give the solidity contract without any other thing...the response should start with on //MIT license thingy and not anything else...as your response would be sent to the demo_contract_script.s.sol and your output as it is should be compilable there..i dont even want \`\`\` in the beginning and end...just the code.
        also dont make any error, last time you were using assert and passing 2 paramenters to it, you should've used require instead

CONTRACT:
${contract_data}

Generate properties that detect:
1. Reentrancy attacks - state consistency before/after external calls
2. Access control flaws - unauthorized function execution  
3. Integer overflow/underflow - arithmetic operation safety
4. Price manipulation - oracle and economic exploits
5. Flash loan attacks - single transaction exploits
6. Governance attacks - voting and proposal manipulation
7. DoS attacks - gas limit and resource exhaustion
8. Time manipulation - block timestamp dependencies
9. Cross-function vulnerabilities - complex state inconsistencies
10. Upgrade vulnerabilities - proxy and storage collisions

For each vulnerability category, create:
- Invariant properties that must always hold
- Fuzzing tests with extreme parameter values
- Edge case scenarios that commonly cause exploits
- Multi-step attack sequence detection

Output format for each property:
\`\`\`solidity
// DETECTS: [specific vulnerability]
// LOGIC: [mathematical relationship being tested]
function invariant_PropertyName() public {
    // test implementation
    assert(condition);
}

function test_PropertyName_Fuzz(uint256 param) public {
    vm.assume(param > 0 && param < type(uint256).max);
    // fuzzing test implementation  
    assert(condition);
}
\`\`\`

Requirements:
- Every property must target a real vulnerability pattern
- Properties must be mathematically rigorous and precise
- Include both positive and negative test cases
- Test extreme values and boundary conditions
- Focus on properties that catch subtle exploits
- Generate comprehensive coverage of all attack vectors

Make the properties so thorough that no vulnerability can escape detection.
also you should make absolutely 0 misatakes..i literally expect no mistake from your side..so keep that in mind brah`,
    });
    return response.text;
}

const script_data = await llm_script_generator();

const script_dir = path.join(__dirname, 'script');
let property_name = property.substring(0, property.length - 4);
const path_to_script = path.join(script_dir, `${property_name}_script.s.sol`);
const writeFile = fs.writeFileSync(path_to_script,
    script_data,
    "utf-8"
);


for (let i = 0; i < 3; i++) {
    //run test on the written file
    const forge_args = [
        "test",
        "--match-path",
        `scripts/${property_name}_script.s.sol`,
        "-vvv"
    ];

    const result = spawnSync("forge", forge_args, { encoding: "utf-8" });

    const properties_content = fs.readFileSync(path_to_script, "utf-8");

    async function llm_error_resolve() {
        const response = await ai.models.generateContent({
            model: "gemini-2.5-flash",
            contents: `
            You are an elite Solidity engineer and smart contract auditor. 
    Your task is to **rewrite the entire Solidity script** so that it compiles and passes all Foundry tests, while maintaining all previous properties and features.
    
    INPUTS:
    - contract properties content ${properties_content}
    - Original contract content: ${contract_data}
    - Forge test stdout: ${result.stdout}
    - Forge test stderr: ${result.stderr}
    - Forge exit code: ${result.status}
    
    TASKS:
    1. Resolve all compilation and runtime errors that appear in the Forge output.
    2. Ensure that there are **no remaining syntax or semantic errors** in the contract or test script.
    3. Keep all vulnerability-focused properties generated previously (reentrancy, access control, integer overflow/underflow, price manipulation, flash loans, governance, DoS, time manipulation, cross-function issues, upgrade/proxy issues).
    4. Apply corrections where needed, including fixes to asserts, requires, fuzzing tests, invariants, and boundary cases.
    5. Optimize for **minimal errors**, correctness, and Solidity best practices.
    
    REQUIREMENTS:
    - Return **only** the complete, corrected Solidity code.
    - Start with the SPDX license header
    - Do not add explanations, comments, or markdown code fences.
    - Ensure the code is immediately compilable and ready to pass "forge test" when run in terminal using foundry.
    
    CONSTRAINT:
    - Treat the Forge output as authoritative: any error reported must be fixed.
    - Also check for any overlooked syntactic or logical issues not reported by Forge, and fix them preemptively.
    
    OUTPUT:
    - The full corrected contract/test script content that can overwrite scripts/c_script.s.sol directly.
            `
        });
        return response.text;
    };

    const error_resolved_responst = await llm_error_resolve();
    const newwriteFile = fs.writeFileSync(path_to_script,
        script_data,
        "utf-8"
    );
}

