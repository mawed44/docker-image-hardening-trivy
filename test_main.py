import unittest

from main import app


class ApiTests(unittest.TestCase):
    def setUp(self):
        app.config["TESTING"] = True
        self.client = app.test_client()

    def test_home(self):
        response = self.client.get("/")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "application/json")
        self.assertEqual(response.get_json(), {"message": "Container Hardening Lab"})

    def test_health(self):
        response = self.client.get("/health")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.mimetype, "application/json")
        self.assertEqual(response.get_json(), {"status": "ok"})

    def test_unknown_path(self):
        self.assertEqual(self.client.get("/unknown").status_code, 404)

    def test_unknown_health_subpath(self):
        self.assertEqual(self.client.get("/health/unknown").status_code, 404)

    def test_post_home_rejected(self):
        self.assertEqual(self.client.post("/").status_code, 405)

    def test_post_health_rejected(self):
        self.assertEqual(self.client.post("/health").status_code, 405)


if __name__ == "__main__":
    unittest.main()
