import sys
import os
import random
import warnings
from botorch.exceptions import BadInitialCandidatesWarning
import time
import torch

# seed for randomness
current_time = int(time.time() * 1000) % (2**32)
random.seed(current_time)
torch.manual_seed(current_time)

# suppress specific BoTorch warnings to keep the simulation log clean
# these warnings occur when the BO reaches a plateau, which is typical and excpected
warnings.filterwarnings("ignore", category=BadInitialCandidatesWarning)

# dynamically load the PyTorch environment paths so the DPI-C wrapper can find them
try:
    with open('.python_paths.txt', 'r') as f:
        torch_path = f.read().strip()
    if torch_path:
        sys.path.insert(0, torch_path) 
except Exception as e:
    print(f"[Python] Warning: Could not read .python_paths.txt: {e}")

# import BoTorch/GPyTorch modules for BO
# GPyTorch for building the Gaussian model
from botorch.models import SingleTaskGP
from botorch.fit import fit_gpytorch_mll
from gpytorch.mlls import ExactMarginalLogLikelihood
from botorch.acquisition import ExpectedImprovement
from botorch.optim import optimize_acqf
from botorch.models.transforms.outcome import Standardize

# 4D Search Space Bounds: [p_req_m1, p_req_m2, p_req_m3, p_N]
# Row 0 defines the minimums, Row 1 defines the maximums.
# cap p_N at 0.4 (which maps to ~4 cycles max) to increase nb_interrupts toggles
BOUNDS = torch.tensor([
    [0.0, 0.0, 0.0, 0.0], 
    [1.0, 1.0, 1.0, 0.4]  
], dtype=torch.float64)

class BayesianAgent:
    def __init__(self):
        # initialize internal tensors to track the history of the simulation
        # train_x stores every 4D constraint array we have tried (the actions)
        # train_y stores the resulting coverage jump for each try (the rewards)
        self.train_x = torch.empty((0, 4), dtype=torch.float64)
        self.train_y = torch.empty((0, 1), dtype=torch.float64)
        self.best_f = 0.0 # Tracks the highest coverage delta 
        
    def step(self, prev_x_list, delta_cov):
        # Gaussian processes crash if multiple identical X inputs produce identical Y outputs (singular covariance matrix)
        # add tiny random noise to the coverage delta
        epsilon = random.uniform(0.0001, 0.0009)
        noisy_cov = delta_cov + epsilon

        # data conversion: C++ arrays into PyTorch tensors
        new_x = torch.tensor([prev_x_list], dtype=torch.float64)
        new_y = torch.tensor([[noisy_cov]], dtype=torch.float64)
        
        # append the new observation to the dataset
        self.train_x = torch.cat([self.train_x, new_x])
        self.train_y = torch.cat([self.train_y, new_y])
        self.best_f = self.train_y.max().item()

        # generate values for the surrogate model
        # manually test the absolute extremes of the DUT (spamming M1, M3, and ties)
        # added spamming M3 because it was receiving less hits
        if len(self.train_x) == 1:
            return [0.8, 0.05, 0.05, 0.1] # high probability of M1 requesting
        elif len(self.train_x) == 2:
            return [0.05, 0.05, 0.9, 0.1] # high probability of M3 requesting
        elif len(self.train_x) == 3:
            return [0.0, 0.9, 0.9, 0.2]   # high probability of M2/M3 ties
        
        # after extreme cases were covered, use random testing to create the rest of the model
        # random testing creates variance, which improves the model
        elif len(self.train_x) < 8:
            return torch.rand(4, dtype=torch.float64).tolist()

        # now build the surrogate model with the collected values
        # outcome Standardize(m=1) normalizes the coverage rewards 
        gp_model = SingleTaskGP(
            self.train_x, 
            self.train_y, 
            outcome_transform=Standardize(m=1) 
        )
        
        # mll (Marginal Log Likelihood) evaluates how well the GP fits the observed data
        # fit_gpytorch_mll runs an internal optimization loop to tune the GP's hyperparameters (lengthscales and noise) to match the DUTs behavior
        mll = ExactMarginalLogLikelihood(gp_model.likelihood, gp_model)
        fit_gpytorch_mll(mll)

        # Expected Improvement (EI) is the policy that decides what to do next
        # it scans the GP's internal map and mathematically balances exploration and exploitation
        EI = ExpectedImprovement(gp_model, best_f=self.best_f)

        # optimize_acqf searches the continuous 4D bounded space to find the exact 
        # [p_req_m1, p_req_m2, p_req_m3, p_N] array that maximizes the EI function
        # uses random restarts to avoid getting stuck in local maxima
        candidate, _ = optimize_acqf(
            acq_function=EI,
            bounds=BOUNDS,
            q=1,              # return exactly 1 set of constraints
            num_restarts=10,  # try 10 different starting points for the internal search
            raw_samples=50,   # sample 50 random points to seed the restarts
        )
        
        # convert the PyTorch tensor back to a standard Python list to pass back to C++/SV
        return candidate.squeeze().tolist()
