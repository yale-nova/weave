# tests/test_math.py
import unittest
import numpy as np
import scipy.linalg as linalg

class TestNumpyAndScipy(unittest.TestCase):
    def test_dot(self):
        self.assertTrue(np.dot([1, 2], [3, 4]) == 11)

    def test_cholesky(self):
        A = np.array([[1, 0], [0, 2]])
        _ = linalg.cholesky(A)

if __name__ == '__main__':
    unittest.main()

