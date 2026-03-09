import yaml, glob, os, sys

def validate():
    files = glob.glob('.github/workflows/*.yml')
    all_valid = True
    for f in files:
        try:
            with open(f, 'r') as stream:
                content = stream.read().strip()
                if not content:
                    print(f"❌ EMPTY FILE: {f}")
                    all_valid = False
                    continue

                # 1. Basic YAML parse
                try:
                    data = yaml.safe_load(content)
                except Exception as e:
                    print(f"❌ YAML SYNTAX ERROR: {f}\n{e}")
                    all_valid = False
                    continue
                
                if data is None:
                    print(f"❌ EMPTY ROOT (None): {f}")
                    all_valid = False
                    continue

                if not isinstance(data, dict):
                    print(f"❌ INVALID ROOT (not a dict): {f} (got {type(data)})")
                    all_valid = False
                    continue

                # 2. Check for common GHA failures - differentiate between jobs and reusable calls
                if 'jobs' not in data:
                    print(f"❌ NO JOBS DEFINED: {f}")
                    all_valid = False
                else:
                    for job_name, job in data['jobs'].items():
                        if not job or not isinstance(job, dict):
                             print(f"❌ JOB {job_name} is empty: {f}")
                             all_valid = False
                             continue
                        
                        # Reusable workflows use 'uses' instead of 'steps'
                        if 'steps' not in job and 'uses' not in job:
                             print(f"❌ JOB {job_name} has neither steps nor uses: {f}")
                             all_valid = False
                             continue
                        
                        if 'steps' in job:
                            if not isinstance(job['steps'], list):
                                 print(f"❌ JOB {job_name} steps is not a list: {f}")
                                 all_valid = False
                                 continue
                            for i, step in enumerate(job['steps']):
                                 if not any(k in step for k in ['name', 'uses', 'run', 'id', 'with', 'env', 'continue-on-error']):
                                     print(f"❌ STEP {i} in JOB {job_name} is invalid (empty): {f}")
                                     all_valid = False

        except Exception as e:
            print(f"❌ SYSTEM ERROR checking {f}: {e}")
            import traceback
            traceback.print_exc()
            all_valid = False
    
    if all_valid:
        print("✅ ALL WORKFLOWS VALID")
    else:
        sys.exit(1)

if __name__ == '__main__':
    validate()
