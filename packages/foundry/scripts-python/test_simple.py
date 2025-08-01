#!/usr/bin/env python3
"""
Simple test script to check if Python is working
"""

import sys
import os

def main():
    print("✅ Python is working!")
    print(f"Python version: {sys.version}")
    print(f"Current directory: {os.getcwd()}")
    print(f"Script directory: {os.path.dirname(__file__)}")
    
    # Test imports
    try:
        import argparse
        print("✅ argparse imported successfully")
    except ImportError as e:
        print(f"❌ argparse import failed: {e}")
    
    try:
        from pathlib import Path
        print("✅ pathlib imported successfully")
    except ImportError as e:
        print(f"❌ pathlib import failed: {e}")
    
    try:
        from typing import Dict, Any
        print("✅ typing imported successfully")
    except ImportError as e:
        print(f"❌ typing import failed: {e}")

if __name__ == '__main__':
    main() 