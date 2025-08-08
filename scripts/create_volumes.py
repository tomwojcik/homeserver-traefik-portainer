#!/usr/bin/env python3
"""
Script to create all local volumes for Docker stacks.

This script dynamically discovers and creates all necessary local directories
for bind mounts by parsing Docker Compose files using regex patterns.
Named volumes are handled by Docker itself and don't require manual creation.
"""

import os
import sys
import re
from pathlib import Path


def create_directory(path, description="", dry_run=False):
    """Create a directory if it doesn't exist."""
    if dry_run:
        print(f"[DRY RUN] Would create: {path} {description}")
        return True
    
    try:
        Path(path).mkdir(parents=True, exist_ok=True)
        print(f"✓ Created: {path} {description}")
        return True
    except PermissionError:
        print(f"✗ Permission denied: {path} {description}")
        return False
    except Exception as e:
        print(f"✗ Error creating {path}: {e}")
        return False


def extract_volumes_from_compose(compose_file, stack_name):
    """Extract volume paths from a Docker Compose file using regex."""
    volumes = {
        'bind_mounts': [],
        'named_volumes': []
    }
    
    try:
        with open(compose_file, 'r') as f:
            content = f.read()
        
        # Pattern to match volume entries like "- /path/on/host:/path/in/container"
        # More specific pattern that requires the host path to start with / or be a named volume
        volume_pattern = r'^\s*-\s+([/\w][\w\-_./]*):([^:\s]+)(?::([^\s]+))?$'
        
        # Look for volumes section in services
        in_volumes_section = False
        current_service = None
        
        for line in content.split('\n'):
            stripped_line = line.strip()
            
            # Track if we're in a volumes section of a service
            if re.match(r'^\s*\w+:\s*$', line) and not line.startswith('  '):
                current_service = stripped_line.rstrip(':')
                in_volumes_section = False
            elif stripped_line == 'volumes:' and current_service:
                in_volumes_section = True
                continue
            elif in_volumes_section and not line.startswith('      ') and stripped_line and not line.startswith('    -'):
                in_volumes_section = False
            
            if in_volumes_section:
                match = re.match(volume_pattern, line)
                if match:
                    host_path = match.group(1).strip()
                    container_path = match.group(2).strip()
                    options = match.group(3).strip() if match.group(3) else None
                    
                    # Only process actual file system paths that need directory creation
                    if (host_path.startswith('/volume1/docker') and not is_system_path(host_path)):
                        volumes['bind_mounts'].append({
                            'host_path': host_path,
                            'container_path': container_path,
                            'options': options,
                            'stack': stack_name
                        })
        
        # Extract named volumes from volumes section
        volumes_section_match = re.search(r'^volumes:\s*$(.+?)^(?=\w|\s*$)', content, re.MULTILINE | re.DOTALL)
        if volumes_section_match:
            volumes_content = volumes_section_match.group(1)
            for line in volumes_content.split('\n'):
                if line.strip() and ':' in line:
                    volume_name = line.split(':')[0].strip()
                    if volume_name and not volume_name.startswith('#'):
                        volumes['named_volumes'].append({
                            'name': volume_name,
                            'stack': stack_name
                        })
    
    except Exception as e:
        print(f"✗ Error reading {compose_file}: {e}")
    
    return volumes


def is_system_path(path):
    """Check if a path is a system path that shouldn't be created."""
    system_prefixes = [
        '/var/run/',
        '/sys/',
        '/proc/',
        '/etc/',
        '/dev/',
        '/run/',
        '/tmp/'
    ]
    return any(path.startswith(prefix) for prefix in system_prefixes)


def discover_stacks():
    """Discover all Docker Compose stacks in the stacks directory."""
    stacks_dir = Path(__file__).parent.parent / 'stacks'
    stacks = []
    
    if not stacks_dir.exists():
        print(f"✗ Stacks directory not found: {stacks_dir}")
        return stacks
    
    for stack_dir in stacks_dir.iterdir():
        if stack_dir.is_dir():
            compose_file = stack_dir / 'docker-compose.yml'
            if compose_file.exists():
                stacks.append({
                    'name': stack_dir.name,
                    'compose_file': compose_file
                })
    
    return stacks


def main():
    """Create all local volume directories for the stacks."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Create local volume directories for Docker stacks")
    parser.add_argument("--dry-run", action="store_true", help="Show what would be created without actually creating directories")
    args = parser.parse_args()
    
    if args.dry_run:
        print("DRY RUN MODE - No directories will be created")
    
    print("Discovering Docker stacks and extracting volumes...")
    print("=" * 60)
    
    stacks = discover_stacks()
    if not stacks:
        print("✗ No Docker stacks found!")
        return 1
    
    print(f"Found {len(stacks)} stacks:")
    for stack in stacks:
        print(f"  - {stack['name']}")
    
    all_bind_mounts = []
    all_named_volumes = []
    
    print("\nExtracting volumes from compose files:")
    for stack in stacks:
        print(f"\n📁 Processing {stack['name']}...")
        volumes = extract_volumes_from_compose(stack['compose_file'], stack['name'])
        
        bind_count = len(volumes['bind_mounts'])
        named_count = len(volumes['named_volumes'])
        print(f"   Found {bind_count} bind mounts, {named_count} named volumes")
        
        all_bind_mounts.extend(volumes['bind_mounts'])
        all_named_volumes.extend(volumes['named_volumes'])
    
    # Create directories for bind mounts
    print(f"\nCreating directories for {len(all_bind_mounts)} bind mounts:")
    success_count = 0
    
    # Group by host path to avoid duplicates
    unique_paths = {}
    for mount in all_bind_mounts:
        host_path = mount['host_path']
        if host_path not in unique_paths:
            unique_paths[host_path] = mount
    
    for host_path, mount in unique_paths.items():
        if create_directory(host_path, f"({mount['stack']})", dry_run=args.dry_run):
            success_count += 1
    
    # Report named volumes
    if all_named_volumes:
        print(f"\nNamed volumes (managed by Docker):")
        for volume in all_named_volumes:
            print(f"  - {volume['name']} ({volume['stack']})")
    
    print("\n" + "=" * 60)
    print(f"Summary: {success_count}/{len(unique_paths)} directories created successfully")
    
    if success_count == len(unique_paths):
        print("✓ All local volumes created successfully!")
        if all_named_volumes:
            print(f"✓ {len(all_named_volumes)} named volumes will be managed by Docker")
    else:
        print("✗ Some directories could not be created. Check permissions.")
        return 1
    
    return 0


if __name__ == "__main__":
    sys.exit(main())