#!/usr/bin/env python3
"""
Environment Variable Loader for DetoxHook
==========================================

This script loads environment variables from .env files and exports them
to the current environment. It supports multiple .env file locations and
provides safe handling of sensitive data.

Usage:
    python load_env.py [--env-file PATH] [--verbose] [--dry-run]
    
Examples:
    python load_env.py                              # Load from default .env
    python load_env.py --env-file .env.local        # Load from specific file
    python load_env.py --verbose                    # Show loaded variables (non-sensitive)
    python load_env.py --dry-run                    # Show what would be loaded
"""

import os
import sys
import argparse
from pathlib import Path
from typing import Dict, List, Optional


class EnvLoader:
    """Loads environment variables from .env files safely."""
    
    # Sensitive variable patterns (never show values in logs)
    SENSITIVE_PATTERNS = [
        'KEY', 'SECRET', 'PASSWORD', 'TOKEN', 'PRIVATE',
        'MNEMONIC', 'SEED', 'API_KEY', 'DEPLOYMENT_KEY'
    ]
    
    def __init__(self, env_file: Optional[str] = None, verbose: bool = False, dry_run: bool = False):
        self.env_file = env_file or '.env'
        self.verbose = verbose
        self.dry_run = dry_run
        self.loaded_vars: Dict[str, str] = {}
        
    def find_env_file(self) -> Optional[Path]:
        """Find the .env file in the project structure."""
        current_dir = Path.cwd()
        
        # Search order: current dir, parent dirs up to project root
        search_paths = [
            current_dir / self.env_file,
            current_dir.parent / self.env_file,
            current_dir.parent.parent / self.env_file,
            current_dir.parent.parent.parent / self.env_file,
        ]
        
        for path in search_paths:
            if path.exists() and path.is_file():
                return path
                
        return None
    
    def is_sensitive_var(self, var_name: str) -> bool:
        """Check if a variable name contains sensitive data."""
        var_upper = var_name.upper()
        return any(pattern in var_upper for pattern in self.SENSITIVE_PATTERNS)
    
    def parse_env_file(self, file_path: Path) -> Dict[str, str]:
        """Parse .env file and return key-value pairs."""
        env_vars = {}
        
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                for line_num, line in enumerate(file, 1):
                    line = line.strip()
                    
                    # Skip empty lines and comments
                    if not line or line.startswith('#'):
                        continue
                    
                    # Parse KEY=VALUE format
                    if '=' in line:
                        key, value = line.split('=', 1)
                        key = key.strip()
                        value = value.strip()
                        
                        # Remove quotes if present
                        if value.startswith('"') and value.endswith('"'):
                            value = value[1:-1]
                        elif value.startswith("'") and value.endswith("'"):
                            value = value[1:-1]
                        
                        env_vars[key] = value
                    else:
                        if self.verbose:
                            print(f"⚠️  Skipping malformed line {line_num}: {line}")
                            
        except Exception as e:
            print(f"❌ Error reading {file_path}: {e}")
            return {}
            
        return env_vars
    
    def load_environment(self) -> bool:
        """Load environment variables from .env file."""
        
        # Find the .env file
        env_path = self.find_env_file()
        if not env_path:
            print(f"❌ Could not find {self.env_file} in project structure")
            return False
        
        if self.verbose:
            print(f"📂 Found .env file: {env_path}")
        
        # Parse the .env file
        env_vars = self.parse_env_file(env_path)
        if not env_vars:
            print(f"⚠️  No environment variables found in {env_path}")
            return False
        
        # Process variables
        self.loaded_vars = env_vars
        loaded_count = 0
        updated_count = 0
        
        for key, value in env_vars.items():
            if self.dry_run:
                status = "NEW" if key not in os.environ else "UPDATE"
                display_value = "***HIDDEN***" if self.is_sensitive_var(key) else value
                print(f"🔧 [{status}] {key}={display_value}")
            else:
                # Set the environment variable
                was_existing = key in os.environ
                os.environ[key] = value
                
                if was_existing:
                    updated_count += 1
                else:
                    loaded_count += 1
                
                if self.verbose:
                    status = "UPDATED" if was_existing else "LOADED"
                    display_value = "***HIDDEN***" if self.is_sensitive_var(key) else value
                    print(f"✅ [{status}] {key}={display_value}")
        
        # Summary
        if self.dry_run:
            total = len(env_vars)
            print(f"\n📊 Summary: {total} variables would be processed")
        else:
            total = loaded_count + updated_count
            print(f"\n📊 Summary: {loaded_count} new, {updated_count} updated, {total} total variables loaded")
            
        return True
    
    def export_to_shell(self, shell_file: str = "env_exports.sh") -> bool:
        """Export loaded variables to a shell script file."""
        if not self.loaded_vars:
            print("❌ No variables loaded to export")
            return False
        
        try:
            with open(shell_file, 'w', encoding='utf-8') as f:
                f.write("#!/bin/bash\n")
                f.write("# Auto-generated environment exports\n")
                f.write(f"# Generated from: {self.env_file}\n\n")
                
                for key, value in self.loaded_vars.items():
                    # Escape special characters for shell
                    escaped_value = value.replace('"', '\\"').replace('$', '\\$')
                    f.write(f'export {key}="{escaped_value}"\n')
                
                f.write(f"\necho '✅ Exported {len(self.loaded_vars)} environment variables'\n")
            
            # Make the script executable
            os.chmod(shell_file, 0o755)
            
            print(f"📝 Exported variables to {shell_file}")
            print(f"💡 Run: source {shell_file}")
            return True
            
        except Exception as e:
            print(f"❌ Error creating shell export file: {e}")
            return False


def main():
    """Main function to handle command line arguments and execute the loader."""
    parser = argparse.ArgumentParser(
        description="Load environment variables from .env files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s                              # Load from default .env
  %(prog)s --env-file .env.local        # Load from specific file
  %(prog)s --verbose                    # Show loaded variables (non-sensitive)
  %(prog)s --dry-run                    # Show what would be loaded
  %(prog)s --export-shell               # Create shell export script
        """
    )
    
    parser.add_argument(
        '--env-file', '-f',
        default='.env',
        help='Path to .env file (default: .env)'
    )
    
    parser.add_argument(
        '--verbose', '-v',
        action='store_true',
        help='Show detailed output (sensitive values will be hidden)'
    )
    
    parser.add_argument(
        '--dry-run', '-n',
        action='store_true',
        help='Show what would be loaded without actually loading'
    )
    
    parser.add_argument(
        '--export-shell', '-e',
        action='store_true',
        help='Create a shell script to export variables'
    )
    
    parser.add_argument(
        '--shell-file',
        default='env_exports.sh',
        help='Output file for shell export script (default: env_exports.sh)'
    )
    
    args = parser.parse_args()
    
    # Create and run the loader
    loader = EnvLoader(
        env_file=args.env_file,
        verbose=args.verbose,
        dry_run=args.dry_run
    )
    
    print("🔧 DetoxHook Environment Loader")
    print("=" * 35)
    
    success = loader.load_environment()
    
    if success and args.export_shell and not args.dry_run:
        loader.export_to_shell(args.shell_file)
    
    return 0 if success else 1


if __name__ == '__main__':
    sys.exit(main()) 