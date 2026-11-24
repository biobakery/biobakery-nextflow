import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator
from jsonschema.validators import validator_for


REPOSITORY_ROOT = Path(__file__).resolve().parents[2]
RESOURCE_DIRECTORY = REPOSITORY_ROOT / "resources" / "compatibility"
SCHEMA_PATH = RESOURCE_DIRECTORY / "tool-database-comaptibility.schema.json"
RESOURCE_PATH = RESOURCE_DIRECTORY / "tool-database-comaptibility.json"


class CompatibilityResourceSchemaTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.resource = json.loads(RESOURCE_PATH.read_text(encoding="utf-8"))

    def test_schema_is_valid_draft_2020_12(self):
        schema_validator = validator_for(self.schema)
        self.assertIs(schema_validator, Draft202012Validator)
        schema_validator.check_schema(self.schema)

    def test_resource_conforms_to_schema(self):
        validator = Draft202012Validator(
            self.schema,
            format_checker=Draft202012Validator.FORMAT_CHECKER,
        )
        errors = sorted(
            validator.iter_errors(self.resource),
            key=lambda error: list(error.absolute_path),
        )
        self.assertEqual(
            errors,
            [],
            "\n".join(
                f"{'/'.join(map(str, error.absolute_path)) or '<root>'}: "
                f"{error.message}"
                for error in errors
            ),
        )

    def test_initial_resource_claims_no_supported_pairings(self):
        self.assertEqual(self.resource["pairs"], [])


if __name__ == "__main__":
    unittest.main()
