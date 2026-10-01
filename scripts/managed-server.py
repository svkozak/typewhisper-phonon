#!/usr/bin/env python3
"""Run the pinned Fermion server for one owning plugin instance.

Configuration arrives on stdin; EOF or parent death ends this process, including
when TypeWhisper crashes. No shell, subprocess, or credentials in process arguments.
"""
import json
import os
from pathlib import Path
import sys
import threading
import time


def configure_tls():
    # This standalone application must configure SSL before importing clients.
    # Use macOS Keychain trust, including managed organisation certificates.
    # Certificate and hostname verification remain enabled.
    import truststore
    truststore.inject_into_ssl()


def main():
    config = json.loads(sys.stdin.readline())
    parent = os.getppid()

    def watch_pipe():
        while os.read(0, 65536):
            pass
        os._exit(0)

    def watch_parent():
        while True:
            if os.getppid() != parent:
                os._exit(0)
            time.sleep(1)

    threading.Thread(target=watch_pipe, daemon=True).start()
    threading.Thread(target=watch_parent, daemon=True).start()

    configure_tls()
    from fermion import server
    from fermion.cli import main as fermion_main

    original_server = server.ThreadingHTTPServer

    class OwnedServer(original_server):
        def server_activate(self):
            super().server_activate()
            # Port 0 lets the OS choose an unused loopback port atomically.
            destination = Path(config['ready_file'])
            temporary = destination.with_suffix('.tmp')
            with temporary.open('w', encoding='utf-8') as file:
                json.dump({'port': self.server_address[1], 'pid': os.getpid(),
                           'instance': config['instance']}, file)
            os.chmod(temporary, 0o600)
            os.replace(temporary, destination)

    server.ThreadingHTTPServer = OwnedServer
    sys.argv = ['fermion', 'serve', 'phonon-2', '--host', '127.0.0.1',
                '--port', '0', '--api-key', config['token']]
    fermion_main()


if __name__ == '__main__':
    main()
