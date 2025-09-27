import { fileURLToPath } from "url";
import { GoogleGenAI } from "@google/genai";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

dotenv.config();
const ai = new GoogleGenAI(process.env.GEMINI_API_KEY);

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const path_to_contract = path.join(__dirname, 'src', 'demo_contract.sol');
const contract_data = fs.readFileSync(path_to_contract, "utf-8");

console.log("contract loaded succesfully");

async function llm_script_generator() {
    const response = await ai.models.generateContent({
        model: "gemini-2.5-flash",
        contents: `You are an elite smart contract security auditor. Generate comprehensive vulnerability-focused properties for this Solidity contract as Foundry tests.
        You only have to give the solidity contract without any other thing...the response should start with on //MIT license thingy and not anything else...as your response would be sent to the demo_contract_script.s.sol and your output as it is should be compilable there..i dont even want \`\`\` in the beginning and end...just the code.

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

Make the properties so thorough that no vulnerability can escape detection.`,
    });
    return response.text;
}

const script_data = await llm_script_generator();

const script_dir = path.join(__dirname,'script');
const path_to_script = path.join(script_dir, 'demo_contract_script.s.sol');
const writeFile = fs.writeFileSync(path_to_script,
    script_data,
    "utf-8"
);
