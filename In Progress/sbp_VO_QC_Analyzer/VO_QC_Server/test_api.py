#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for VO QC Server API
Demonstrates how to use the /analyze endpoint
"""

import json
import requests
import sys
from pathlib import Path

def test_health():
    """Test server health"""
    print("[TEST] Checking server health...")
    try:
        response = requests.get("http://localhost:5000/health", timeout=5)
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"ERROR: {e}")
        return False

def test_analyze():
    """Test analyze endpoint with dummy data"""
    print("\n[TEST] Testing /analyze endpoint...")
    
    # Create dummy request
    test_request = {
        "audio_files": [
            {
                "path": "C:/nonexistent/audio1.wav",
                "guid": "test-guid-1",
                "index": 0
            }
        ],
        "script_lines": [
            "Hello world",
            "Good morning"
        ],
        "language": "uk",
        "detection_flags": {
            "mismatches": True,
            "duplicates": True,
            "off_script": True,
            "missing": True
        },
        "duplicate_gap_threshold": 1.0,
        "similarity_threshold": 0.85
    }
    
    print("Request:")
    print(json.dumps(test_request, indent=2))
    
    try:
        response = requests.post(
            "http://localhost:5000/analyze",
            json=test_request,
            timeout=10
        )
        print(f"\nStatus: {response.status_code}")
        print("Response:")
        print(json.dumps(response.json(), indent=2, ensure_ascii=False))
        return response.status_code in [200, 400]  # Both are valid (error is expected for no file)
    except Exception as e:
        print(f"ERROR: {e}")
        return False

def test_info():
    """Get server info"""
    print("\n[TEST] Getting server info...")
    try:
        response = requests.get("http://localhost:5000/info", timeout=5)
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"ERROR: {e}")
        return False

if __name__ == "__main__":
    print("=" * 60)
    print("VO QC Server - API Test Suite")
    print("=" * 60)
    
    # Check if server is running
    print("\nConnecting to http://localhost:5000\n")
    
    tests = [
        ("Health Check", test_health),
        ("Info Endpoint", test_info),
        ("Analyze Endpoint", test_analyze),
    ]
    
    passed = 0
    for test_name, test_func in tests:
        try:
            if test_func():
                passed += 1
                print(f"✓ {test_name} PASSED")
            else:
                print(f"✗ {test_name} FAILED")
        except Exception as e:
            print(f"✗ {test_name} ERROR: {e}")
    
    print("\n" + "=" * 60)
    print(f"Results: {passed}/{len(tests)} tests passed")
    print("=" * 60)
    
    if passed == len(tests):
        print("\n✓ All tests passed! Server is working correctly.")
        sys.exit(0)
    else:
        print("\n✗ Some tests failed. Check server logs.")
        sys.exit(1)
