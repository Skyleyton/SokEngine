import subprocess
import sys
import time
import platform

# For one command
def process_command(command_name: str) -> bool:
    code = subprocess.run(command_name, shell=True).returncode
    if code == 0:
        return True
    
    return False

# For multiple commands
def process_commands(command_list: list[str]) -> bool:
    good = 0
    for command in command_list:
        if process_command(command):
            good += 1
    
    if len(command_list) == good:
        return True

    return False

def main():
    platform_used = platform.system()
    # Need some arguments.
    if len(sys.argv) != 2:
        print("build.py <build | run>")
        return
    
    if platform_used == "Windows":
        # Build mode
        if sys.argv[1] == "build":
            start = time.time()
            if process_commands([".\\generate_shader.bat", "odin build source/ -debug -define:SOKOL_USE_GL=true"]):
                print("Build finished without error")
                end = time.time()
                build_time = end - start
                print(f"Build Time: {build_time}s")
                return
    
        # Run mode
        if sys.argv[1] == "run":
            process_commands([".\\generate_shader.bat", "odin run source/ -debug -define:SOKOL_USE_GL=true"])
            return

    if platform_used == "Linux":
        # Build mode
        if sys.argv[1] == "build":
            start = time.time()
            if process_commands(["./generate_shader.sh", "odin build source/ -debug -define:SOKOL_USE_GL=true"]):
                print("Build finished without error")
                end = time.time()
                build_time = end - start
                print(f"Build Time: {build_time}s")
                return
    
        # Run mode
        if sys.argv[1] == "run":
            process_commands(["./generate_shader.sh", "odin run source/ -debug -define:SOKOL_USE_GL=true"])
            return

if __name__ == "__main__":
    main()
