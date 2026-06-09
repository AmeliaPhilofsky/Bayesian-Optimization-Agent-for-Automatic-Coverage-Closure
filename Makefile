# target definitions
QUESTA_INC ?= /usr/local/apps/mentor/questa/include

# fetch Python C-API paths for the active environment
PYTHON_INC := $(shell python3-config --cflags)
PYTHON_LIB := $(shell python3-config --ldflags --embed)

SV_FILES   = controller.sv tb.sv
CPP_SOURCE = dpi_wrapper.cpp
SHARED_LIB = dpi_lib.so
DPI_HEADER = dpi_stubs.h

# default target
all: work compile_sv compile_cpp run

work:
	vlib work

compile_sv: $(SV_FILES) | work
	vlog -cover sbceft -dpiheader $(DPI_HEADER) $(SV_FILES)

# Extract 'libpython3.x.so' dynamically for agent
PY_LIB_NAME := $(shell python3 -c "import sys; print(f'libpython{sys.version_info.major}.{sys.version_info.minor}.so')")

compile_cpp: $(CPP_SOURCE) $(DPI_HEADER)
	g++ -shared -fPIC -DPY_LIB_NAME=\"$(PY_LIB_NAME)\" $(PYTHON_INC) -I$(QUESTA_INC) $(CPP_SOURCE) -o $(SHARED_LIB) $(PYTHON_LIB)

run: compile_sv compile_cpp
	@echo "Starting QuestaSim with Embedded Python..."
	# generate simple simulation script
	@echo "coverage save -onexit cov.ucdb" > sim.do
	@echo "run -all" >> sim.do
	@echo "coverage report -detail -output aggregate_coverage_report.txt" >> sim.do
	@echo "coverage report -html -output cov_html" >> sim.do
	@echo "exit" >> sim.do
	@python3 -c "import site; print(':'.join(site.getsitepackages() + [site.getusersitepackages()]))" > .python_paths.txt
	
	# run simulation
	export LD_LIBRARY_PATH=$(CURDIR):$$LD_LIBRARY_PATH; \
	vsim -c -voptargs="+acc" -suppress 10587 -cvgperinstance -coverage -sv_lib dpi_lib -sv_seed random work.tb -do sim.do
	
clean:
	rm -rf work vsim.wlf $(DPI_HEADER) $(SHARED_LIB) __pycache__ *.rpt cov_html cov.ucdb transcript sim.do .python_paths.txt *_coverage_report.txt
