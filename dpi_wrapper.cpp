#include "svdpi.h"
#include <Python.h>
#include <iostream>
#include <dlfcn.h> // needed for dynamic library loading (the PyTorch fix)

// define the python shared library name 
#ifndef PY_LIB_NAME
#define PY_LIB_NAME "libpython3.so" 
#endif

// global pointers to keep the python script and agent instance alive in memory throughout the entire SystemVerilog simulation
static PyObject *pModule = nullptr;
static PyObject *pAgentInstance = nullptr;

// init_agent(): called once at the start of the simulation to create agent
extern "C" void init_agent() {
    std::cout << "[DPI-C] Initializing Embedded Python Interpreter..." << std::endl;
    
    // prevents crashing since I'm using PyTorch: 
    // PyTorch uses massive C++ extensions, globally load the Python C-API now
    void* handle = dlopen(PY_LIB_NAME, RTLD_LAZY | RTLD_GLOBAL);
    if (!handle) {
        std::cerr << "[DPI-C Warning] dlopen failed on " << PY_LIB_NAME << ". Torch may crash." << std::endl;
    }
    
    // python interpreter inside QuestaSim
    Py_Initialize();
    
    // tell agent to look in the current working directory for the script
    PyRun_SimpleString("import sys; sys.path.append('.')");

    // load the agent
    PyObject *pName = PyUnicode_FromString("my_bayesian_agent");
    pModule = PyImport_Import(pName);
    Py_DECREF(pName); // Clean up memory for the string

    if (pModule != nullptr) {
        // find the agent class inside the python file
        PyObject *pClass = PyObject_GetAttrString(pModule, "BayesianAgent");
        if (pClass && PyCallable_Check(pClass)) {
            // instantiate the agent
            pAgentInstance = PyObject_CallObject(pClass, nullptr);
            Py_DECREF(pClass);
            std::cout << "[DPI-C] Successfully instantiated BayesianAgent." << std::endl;
        } else {
            if (PyErr_Occurred()) PyErr_Print();
            std::cerr << "[DPI-C ERROR] Cannot find BayesianAgent class." << std::endl;
        }
    } else {
        PyErr_Print(); 
        std::cerr << "[DPI-C ERROR] Failed to load my_bayesian_agent.py" << std::endl;
    }
}

// get_new_constraints(): called every iteration of the testbench loop
extern "C" void get_new_constraints(const double prev_x[4], double delta_cov, double next_x[4]) {
    // if python crashed, just return dummy probabilities so SV doesn't hang
    if (!pAgentInstance) {
        next_x[0] = 0.5; next_x[1] = 0.5; next_x[2] = 0.5; next_x[3] = 0.05; 
        return;
    }

    // change data types: convert the C++ double array into a python list
    PyObject *pPrevX = PyList_New(4); 
    for (int i = 0; i < 4; i++) {
        // PyList_SetItem steals the reference, so no need to DECREF the float
        PyList_SetItem(pPrevX, i, PyFloat_FromDouble(prev_x[i]));
    }

    // agent.step(prev_x, delta_cov): BO loop that processes inputs and produces outputs
    // "Od" is the format string: 'O' means Python Object (the list), 'd' means double (delta_cov)
    PyObject *pResult = PyObject_CallMethod(pAgentInstance, "step", "Od", pPrevX, delta_cov);
    Py_DECREF(pPrevX); // Free the input list from memory

    // convert the return values from python
    if (pResult != nullptr && PyList_Check(pResult)) {
        // unpack the returned Python list back into the C++ array for SystemVerilog
        for (int i = 0; i < 4; i++) {
            PyObject *item = PyList_GetItem(pResult, i); 
            next_x[i] = PyFloat_AsDouble(item);
        }
        Py_DECREF(pResult); // free the returned list
    } else {
        PyErr_Print();
        std::cerr << "[DPI-C ERROR] Python step() failed or didn't return a list." << std::endl;
    }
}

// cleanup_agent(): called at the end for memory management and shutdown
extern "C" void cleanup_agent() {
    std::cout << "[DPI-C] Shutting down embedded Python..." << std::endl;
    // delete global python objects
    Py_XDECREF(pAgentInstance);
    Py_XDECREF(pModule);
    // shut down the interpreter to free RAM
    Py_Finalize();
}
