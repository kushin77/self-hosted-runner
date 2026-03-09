import yaml, glob, os

def fix_workflow(f):
    try:
        with open(f, 'r') as s:
            content = s.read()
            
        # 1. Fix "true:" instead of "on:"
        if "\ntrue:\n" in content:
            content = content.replace("\ntrue:\n", "\non:\n")
            
        # 2. Fix broken multi-line 'steps' that have both 'uses' and 'run' in same block incorrectly
        # Or steps that are missing names
        data = yaml.safe_load(content)
        if not data or not isinstance(data, dict): return
        
        changed = False
        if 'jobs' in data:
            for job_id, job in data['jobs'].items():
                if 'steps' in job:
                    new_steps = []
                    for step in job['steps']:
                        # Sanitize steps: must have either 'uses' or 'run'
                        # If a step has neither, it is invalid GHA
                        if 'uses' not in step and 'run' not in step:
                            continue # Drop invalid steps
                        new_steps.append(step)
                    if len(new_steps) != len(job['steps']):
                        job['steps'] = new_steps
                        changed = True
        
        if changed or "\non:\n" in content:
            with open(f, 'w') as s:
                yaml.dump(data, s, sort_keys=False)
            print(f"✅ Repaired {f}")
            
    except Exception as e:
        print(f"❌ Failed to fix {f}: {e}")

files = glob.glob('.github/workflows/*.yml')
for f in files:
    fix_workflow(f)
