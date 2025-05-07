import os

def child():
    print("👶 Child process running!")
    os._exit(0)

def parent(pid):
    print(f"👨 Parent spawned child with pid {pid}")
    os.waitpid(pid, 0)
    print("👨 Parent: child finished")

if __name__ == "__main__":
    pid = os.fork()
    if pid == 0:
        child()
    else:
        parent(pid)

