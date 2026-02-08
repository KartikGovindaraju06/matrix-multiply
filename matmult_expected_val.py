import numpy as np
import sys

def parse_memory_initialization(filepath):
    """
    Parse memory initialization format from file and extract hex values.
    Returns a list of integer values.
    """
    hex_values = []
    
    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            # Skip header lines and empty lines
            if 'memory_initialization' in line or not line:
                continue
            # Remove trailing comma and semicolon
            line = line.rstrip(',').rstrip(';')
            if line:
                hex_values.append(int(line, 16))
    
    return hex_values

def process_matrices(matrix_a_file, matrix_b_file, matrix_c_file):
    """
    Process matrix A (128x128), matrix B (128x1), and matrix C (128x1) from files.
    Split A into 16 segments of 8x128.
    Multiply each segment with B and sum the results.
    Sum all values in C.
    Add the two accumulated sums together.
    """
    print("Reading matrix files...")
    
    # Parse the input files
    a_values = parse_memory_initialization(matrix_a_file)
    b_values = parse_memory_initialization(matrix_b_file)
    c_values = parse_memory_initialization(matrix_c_file)
    
    print(f"Parsed {len(a_values)} values from matrix A")
    print(f"Parsed {len(b_values)} values from matrix B")
    print(f"Parsed {len(c_values)} values from matrix C")
    
    # Verify dimensions
    if len(a_values) != 128 * 128:
        print(f"Warning: Expected 16384 values for 128x128 matrix A, got {len(a_values)}")
        if len(a_values) < 128 * 128:
            print("Error: Insufficient data for 128x128 matrix")
            return
    
    if len(b_values) != 128:
        print(f"Warning: Expected 128 values for matrix B, got {len(b_values)}")
        if len(b_values) < 128:
            print("Error: Insufficient data for 128x1 matrix")
            return
    
    if len(c_values) != 128:
        print(f"Warning: Expected 128 values for matrix C, got {len(c_values)}")
        if len(c_values) < 128:
            print("Error: Insufficient data for 128x1 matrix")
            return
    
    # Convert to numpy arrays
    # Matrix A is in row-major order
    A = np.array(a_values[:128*128], dtype=np.int64).reshape(128, 128)
    B = np.array(b_values[:128], dtype=np.int64).reshape(128, 1)
    C = np.array(c_values[:128], dtype=np.int64).reshape(128, 1)
    
    print(f"\nMatrix A shape: {A.shape}")
    print(f"Matrix B shape: {B.shape}")
    print(f"Matrix C shape: {C.shape}")
    print("\nProcessing 16 segments of matrix A (each 8x128)...\n")
    print("="*70)
    
    # Split matrix A into 16 segments of 8x128 each
    results = []
    for i in range(16):
        start_row = i * 8
        end_row = start_row + 8
        
        # Extract segment (8x128)
        segment = A[start_row:end_row, :]
        
        # Multiply segment (8x128) with B (128x1) to get result (8x1)
        result = segment @ B
        
        # Sum all values in the resulting matrix
        total_sum = np.sum(result)
        
        results.append(total_sum)
        
        print(f"Segment {i+1:2d} (rows {start_row:3d}-{end_row-1:3d}): Sum = {total_sum:15d}")
    
    print("="*70)
    print("\nSummary of all 16 segment sums:")
    print("="*70)
    for i, result in enumerate(results):
        print(f"Segment {i+1:2d}: {result:15d}")
    
    # Calculate accumulated sum from A*B
    accumulated_sum_ab = sum(results)
    
    print("\n" + "="*70)
    print(f"Accumulated sum from A*B: {accumulated_sum_ab:15d}")
    print("="*70)
    
    # Calculate accumulated sum from C
    accumulated_sum_c = np.sum(C)
    
    print("\n" + "="*70)
    print(f"Accumulated sum from C:   {accumulated_sum_c:15d}")
    print("="*70)
    
    # Calculate final sum (A*B + C)
    final_sum = accumulated_sum_ab + accumulated_sum_c
    
    print("\n" + "="*70)
    print(f"FINAL SUM (A*B + C):      {final_sum:15d}")
    print("="*70)

def main():
    if len(sys.argv) != 4:
        print("Usage: python matrix_multiplication.py <matrix_a_file> <matrix_b_file> <matrix_c_file>")
        print("\nExample:")
        print("  python matrix_multiplication.py matrix_a.txt matrix_b.txt matrix_c.txt")
        sys.exit(1)
    
    matrix_a_file = sys.argv[1]
    matrix_b_file = sys.argv[2]
    matrix_c_file = sys.argv[3]
    
    try:
        process_matrices(matrix_a_file, matrix_b_file, matrix_c_file)
    except FileNotFoundError as e:
        print(f"Error: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"Error processing matrices: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)

if __name__ == "__main__":
    main()