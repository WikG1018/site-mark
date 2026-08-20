import unittest


class IntentionalHostGateFailure(unittest.TestCase):
    def test_failure_is_propagated(self) -> None:
        self.fail("intentional host gate failure")


if __name__ == "__main__":
    unittest.main()
