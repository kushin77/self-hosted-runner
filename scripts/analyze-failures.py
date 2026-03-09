import yaml, glob, os

def check_workflow(f):
    with open(f, 'r') as s:
        content = s.read()
        try:
            data = yaml.safe_load(content)
            if not isinstance(data, dict): return "NOT_A_DICT"
            
            # Check for common GHA strict failures
            if 'jobs' not in data: return "NO_JOBS"
            
            for j_id, j in data['jobs'].items():
                if 'steps' in j:
                    for step in j['steps']:
                        if 'run' in step:
                            # 1. Check for illegal character sequences in run blocks
                            if "::set-output" in step['run']: return f"DEPRECATED_SET_OUTPUT_{j_id}"
                            if "·" in step['run']: return f"NON_ASCII_DOT_{j_id}"
                            if "steps." in step['run'] and "${{" not in step['run']: return f"RAW_STEPS_REF_{j_id}"
                        
                        # 2. Check for missing required keys in steps
                        if not any(k in step for k in ['uses', 'run']):
                            return f"STEP_MISSING_USES_OR_RUN_{j_id}"

            return "OK"
        except Exception as e:
            return f"YAML_PARSE_ERROR: {str(e)[:100]}"

files = glob.glob('.github/workflows/*.yml')
for f in sorted(files):
    status = check_workflow(f)
    if status != "OK":
        print(f"{f}: {status}")
