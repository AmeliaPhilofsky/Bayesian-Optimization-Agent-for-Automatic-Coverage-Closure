# 1. Run simulation to the end
run -all

# 2. Save the coverage database (this is the source for reports)
coverage save total_cov.ucdb

# 3. Generate the text report from the saved database
# -cvg includes your manual covergroups
# -details shows the specific bins the AI missed
coverage report -detail -cvg -output cov.rpt

# 4. Generate HTML report
coverage report -html -output cov_html -details -annotate -cvg

# 5. Exit
quit -f
