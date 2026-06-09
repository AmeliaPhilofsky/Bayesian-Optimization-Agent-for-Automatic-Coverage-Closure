# Bayesian Optimization Agent for Automatic Coverage Closure

An ML-driven hardware verification agent that leverages Bayesian Optimization (BO) to automatically achieve 100% functional coverage. Built with Python and PyTorch, this tool integrates seamlessly with QuestaSim via DPI-C to intelligently constrain random input generation and close coverage holes efficiently for a given DUT and covergroups.

## Architecture & Methodology

Standard SystemVerilog constrained random testing relies on blind randomization, which often wastes cycles testing redundant and highly improbable states. While advanced ML techniques like Graph Neural Networks (GNNs) could theoretically map an RTL design's synthesized graph, they require immense training data and time. 

Instead, this project utilizes **Bayesian Optimization** due to its high sample efficiency and rapid start-up time. BO treats the SystemVerilog simulation as a black box, building a probabilistic prediction model (Surrogate Model) during initialization. It actively predicts the specific random constraints needed to reach unverified edge cases by balancing areas known to yield high coverage (exploitation) against untested areas of the design space (exploration). 

### Problem Mapping

The verification challenge maps directly to the standard BO framework:

* **Black-Box Objective Function:** The QuestaSim simulation of the memory controller. The function takes input constraints, runs `N` requests for `M/N` cycles, and outputs the functional coverage percentage. The objective is to maximize this percentage.
* **Search Space:** The boundaries defining the joint probability distribution for the Request class. Specifically, these are the constraint weights applied to `req` (0-7), `done` (0-7), `reset` (0-1), and `NCycles` (1-10).
* **Surrogate Model (Gaussian Process):** Learns the design space, mapping the relationship between distribution constraints and coverage results. It predicts both expected coverage and mathematical uncertainty.
* **Acquisition Function:** The policy determining the next sampling point. It calculates the optimal set of distribution constraints to feed into the testbench to find unreached edge cases.
* **Observations:** A growing dataset of evaluated points, recorded as `(Distribution Parameters, Achieved Coverage)` pairs, updated after every test iteration.

## Execution Flow

To enable automatic coverage collection, a C++ wrapper embeds the PyTorch/BoTorch agent directly into the SystemVerilog testbench using DPI-C.

1. **Initialization:** Compile the design (`controller.v`), testbench (`controller_tb.v`), and covergroups. Initialize the Request class with baseline uniform randomization.
2. **Initial Sampling:** Run a baseline set of tests (`N` requests per test) to generate an initial set of coverage numbers and seed the BO agent.
3. **Model Update:** Feed the distribution parameters and resulting coverage through the DPI-C wrapper into the PyTorch agent. The agent updates its Gaussian Process.
4. **Redirection:** The acquisition function calculates the next optimal distribution to balance exploration and exploitation.
5. **Iteration:** Pass the newly generated distribution parameters back to the SystemVerilog testbench and run the next test.
6. **Termination:** Repeat steps 3–5 until 100% functional coverage is achieved or the maximum number of requests (`M`) is reached.

## Sample Results
<img width="407" height="247" alt="BO_Results" src="https://github.com/user-attachments/assets/2e118519-1d75-4195-b9e0-c7aa6095e14b" />

Testing was conducted across three different configurations, capping each at a maximum of 100 tests (`M/N = 100`). 

* **`N=10, M=1000`**: Did not consistently reach 100% coverage before hitting the 100-test cap.
* **`N=20, M=2000`**: Consistently reached 100% coverage.
* **`N=30, M=3000`**: Consistently reached 100% coverage and yielded the fastest average coverage closure.

Due to the inherent randomness of the agent, the fastest configuration can vary run-to-run (e.g., a slower theoretical configuration may occasionally stumble upon a faster path to 100%). However, because runtime overhead between configurations is negligible, `N=30, M=3000` is the recommended configuration for the fastest and most reliable coverage closure.

---

## Getting Started

### Prerequisites
This algorithm relies on PyTorch, BoTorch, and GPyTorch. Install the required Python libraries using:
```bash
pip install -r install.txt
