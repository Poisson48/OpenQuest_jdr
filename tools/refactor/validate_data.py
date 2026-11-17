#!/usr/bin/env python3
"""validate_data.py — validateur JSON Schema minimaliste, sans dépendance externe.

But (refactor phase 5.3 / ADR-004) : mesurer la dérive réelle entre le contrat
`data/schemas/*.json` et les données JSON du dépôt, sans brancher de validateur
dans le code de jeu pour autant. Le script est autonome (stdlib Python 3.8+),
rejouable et testé par auto-test intégré.

Sous-ensemble JSON Schema supporté (tout le reste est signalé comme
« mot-clé non supporté » dans le rapport) :

    type, properties, required, additionalProperties (bool ou schéma),
    items (schéma ou tuple), enum, const, pattern, minLength, maxLength,
    minimum, maximum, exclusiveMinimum, exclusiveMaximum,
    minItems, maxItems, uniqueItems, minProperties, maxProperties,
    propertyNames, $ref local (« # », « #/$defs/X »), $defs,
    allOf, anyOf, oneOf, not, if/then/else, true/false (schémas booléens).

Annotations ignorées : $schema, $id, title, description, default, examples,
deprecated, readOnly, writeOnly, $comment.

Usages :
    python tools/refactor/validate_data.py
        # auto-test + validation de toutes les paires schéma↔données connues
        # code retour 0 si tout est valide, 1 si dérive ou auto-test en échec
    python tools/refactor/validate_data.py --json > rapport.json
    python tools/refactor/validate_data.py --list        # matrice seule
    python tools/refactor/validate_data.py --only scenario,map
    python tools/refactor/validate_data.py --schema data/schemas/bot.json \
        --data data/bots/archetypes.json --mode array-items
    python tools/refactor/validate_data.py --skip-self-test

Convention de chemin dans les erreurs : `$` = racine, `.clé` = propriété,
`[i]` = indice de tableau (ex. `$.scenes[2].title`).

Aucune dépendance : ce script n'utilise que la bibliothèque standard.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import re
import sys
from typing import Any, Dict, List, Optional, Sequence, Tuple

# ---------------------------------------------------------------------------
# Constantes du contrat : 8 schémas et couples schéma↔données du dépôt.
# ---------------------------------------------------------------------------

SCHEMAS_DIR = "data/schemas"

#: mode "object" = chaque fichier est un objet validé par le schéma ;
#: mode "array-items" = le fichier est un tableau dont chaque élément est validé.
MAPPINGS: List[Dict[str, Any]] = [
    {
        "schema": "scenario",
        "globs": ["data/scenarios/*.json", "game/data/scenarios/*.json"],
        "mode": "object",
        "note": "scénarios jouables (le dossier data/ est un miroir de game/data/)",
    },
    {
        "schema": "map",
        "globs": ["data/maps/*.json", "game/data/maps/*.json"],
        "mode": "object",
        "note": "cartes locales et cartes du monde",
    },
    {
        "schema": "bot",
        "globs": ["data/bots/*.json", "game/data/bots/*.json"],
        "mode": "array-items",
        "note": "archetypes.json contient un tableau d'archétypes de bots",
    },
    {
        "schema": "ruleset",
        "globs": ["game/data/rulesets/*.json"],
        "mode": "object",
        "note": "fiches déclaratives (champs/dérivés/jets/tables)",
    },
    {
        "schema": "character",
        "globs": ["data/characters/*.json", "game/data/characters/*.json"],
        "mode": "object",
        "note": "aucun fichier versionné : les personnages vivent dans user://",
    },
    {"schema": "dice_roll", "globs": [], "mode": "object", "note": "résultat produit à l'exécution, jamais stocké"},
    {"schema": "save_game", "globs": [], "mode": "object", "note": "sauvegardes côté user:// (client), aucun fichier versionné"},
    {"schema": "session_model", "globs": [], "mode": "object", "note": "sous-structures embarquées dans active_game/save_game"},
]

#: Fichiers JSON du dépôt volontairement hors contrat (documentés dans le rapport).
UNCOVERED_REASONS = {
    "data/tiles.json": "catalogue de tuiles (pas de schéma) — miroir de game/data/tiles.json",
    "game/data/tiles.json": "catalogue de tuiles (pas de schéma)",
    "game/data/tests/dice_cases.json": "fixture de test du moteur de dés (spec, pas une donnée de jeu)",
}

ANNOTATION_KEYWORDS = {
    "$schema",
    "$id",
    "$comment",
    "$anchor",
    "title",
    "description",
    "default",
    "examples",
    "deprecated",
    "readOnly",
    "writeOnly",
}

SUPPORTED_KEYWORDS = {
    "$ref",
    "$defs",
    "type",
    "properties",
    "required",
    "additionalProperties",
    "items",
    "enum",
    "const",
    "pattern",
    "minLength",
    "maxLength",
    "minimum",
    "maximum",
    "exclusiveMinimum",
    "exclusiveMaximum",
    "minItems",
    "maxItems",
    "uniqueItems",
    "minProperties",
    "maxProperties",
    "propertyNames",
    "allOf",
    "anyOf",
    "oneOf",
    "not",
    "if",
    "then",
    "else",
}

MAX_DEPTH = 200


class SchemaError(Exception):
    """Erreur interne de schéma (référence cassée, forme invalide…)."""


# ---------------------------------------------------------------------------
# Utilitaires JSON / chemins
# ---------------------------------------------------------------------------


def json_type(value: Any) -> str:
    """Nom JSON Schema du type Python d'une valeur (bool n'est pas un nombre)."""
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    if isinstance(value, str):
        return "string"
    if isinstance(value, list):
        return "array"
    if isinstance(value, dict):
        return "object"
    return "unknown"


def matches_type(value: Any, expected: str) -> bool:
    actual = json_type(value)
    if expected == actual:
        return True
    if expected == "number":
        return actual in ("integer", "number")
    if expected == "integer":
        # JSON Schema : 1.0 est un entier (valeur sans partie fractionnaire).
        return actual == "number" and isinstance(value, float) and value.is_integer()
    return False


def child_path(path: str, key: str) -> str:
    if re.match(r"^[A-Za-z_][A-Za-z0-9_]*$", key):
        return f"{path}.{key}"
    return f'{path}["{key}"]'


def index_path(path: str, index: int) -> str:
    return f"{path}[{index}]"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


# ---------------------------------------------------------------------------
# Validateur
# ---------------------------------------------------------------------------


class SchemaValidator:
    """Validateur d'une instance contre un schéma JSON, sans dépendance."""

    def __init__(self, schema: Any, source: str = "<schéma>") -> None:
        if not isinstance(schema, (dict, bool)):
            raise SchemaError(f"{source} : un schéma doit être un objet ou un booléen.")
        self.root = schema
        self.source = source
        self.schema_errors: List[str] = []
        self.unsupported: set = set()
        self._regex_cache: Dict[str, re.Pattern] = {}

    # -- API ---------------------------------------------------------------
    def validate(self, data: Any) -> List[Tuple[str, str]]:
        """Valide `data` et retourne une liste de (chemin, message)."""
        self.schema_errors = []
        errors: List[Tuple[str, str]] = []
        self._validate(data, self.root, "$", 0, errors)
        return errors

    # -- Résolution $ref ---------------------------------------------------
    def _resolve_ref(self, ref: Any) -> Any:
        if not isinstance(ref, str):
            raise SchemaError(f"$ref non textuel : {ref!r}")
        if not ref.startswith("#"):
            raise SchemaError(f"$ref externe non supporté : {ref}")
        pointer = ref[1:]
        if pointer in ("", "/"):
            return self.root
        if not pointer.startswith("/"):
            raise SchemaError(f"$ref invalide : {ref}")
        node: Any = self.root
        for raw_token in pointer[1:].split("/"):
            token = raw_token.replace("~1", "/").replace("~0", "~")
            if isinstance(node, dict):
                if token not in node:
                    raise SchemaError(f"$ref non résolu : {ref} (clé absente : {token})")
                node = node[token]
            elif isinstance(node, list):
                try:
                    node = node[int(token)]
                except (ValueError, IndexError):
                    raise SchemaError(f"$ref non résolu : {ref} (indice invalide : {token})")
            else:
                raise SchemaError(f"$ref non résolu : {ref}")
        return node

    def _check_refs(self, node: Any, trail: str = "$") -> None:
        """Vérifie que tous les $ref du schéma se résolvent."""
        if isinstance(node, dict):
            for key, value in node.items():
                here = f"{trail}.{key}"
                if key == "$ref":
                    try:
                        self._resolve_ref(value)
                    except SchemaError as exc:
                        self.schema_errors.append(str(exc))
                    continue
                self._check_refs(value, here)
        elif isinstance(node, list):
            for i, value in enumerate(node):
                self._check_refs(value, f"{trail}[{i}]")

    # -- Validation récursive ---------------------------------------------
    def _validate(
        self,
        data: Any,
        schema: Any,
        path: str,
        depth: int,
        errors: List[Tuple[str, str]],
    ) -> None:
        if depth > MAX_DEPTH:
            errors.append((path, f"profondeur de validation dépassée (>{MAX_DEPTH})"))
            return
        if schema is True:
            return
        if schema is False:
            errors.append((path, "valeur interdite par le schéma (false)"))
            return
        if not isinstance(schema, dict):
            self.schema_errors.append(f"{path} : schéma de forme inattendue ({type(schema).__name__})")
            return

        for key in schema:
            if key not in ANNOTATION_KEYWORDS and key not in SUPPORTED_KEYWORDS:
                self.unsupported.add(key)

        # $ref : validé en plus des éventuels mots-clés voisins (2020-12).
        if "$ref" in schema:
            try:
                target = self._resolve_ref(schema["$ref"])
            except SchemaError as exc:
                self.schema_errors.append(str(exc))
                return
            self._validate(data, target, path, depth + 1, errors)

        # type
        if "type" in schema:
            expected = schema["type"]
            expected_list = expected if isinstance(expected, list) else [expected]
            if not any(matches_type(data, str(item)) for item in expected_list):
                label = " | ".join(str(item) for item in expected_list)
                errors.append(
                    (path, f"type attendu '{label}', obtenu '{json_type(data)}'")
                )

        # const / enum
        if "const" in schema and data != schema["const"]:
            errors.append((path, f"valeur attendue (const) : {json.dumps(schema['const'], ensure_ascii=False)}"))
        if "enum" in schema:
            allowed = schema["enum"]
            if not any(data == candidate for candidate in allowed):
                rendered = ", ".join(json.dumps(v, ensure_ascii=False) for v in allowed)
                errors.append((path, f"valeur non autorisée (enum : {rendered})"))

        # Chaînes
        if isinstance(data, str):
            if "minLength" in schema and len(data) < int(schema["minLength"]):
                errors.append((path, f"chaîne trop courte ({len(data)} < minLength {schema['minLength']})"))
            if "maxLength" in schema and len(data) > int(schema["maxLength"]):
                errors.append((path, f"chaîne trop longue ({len(data)} > maxLength {schema['maxLength']})"))
            if "pattern" in schema:
                pattern = schema["pattern"]
                try:
                    compiled = self._regex_cache.get(pattern)
                    if compiled is None:
                        compiled = re.compile(pattern)
                        self._regex_cache[pattern] = compiled
                except re.error as exc:
                    self.schema_errors.append(f"pattern invalide {pattern!r} : {exc}")
                    compiled = None
                if compiled is not None and compiled.search(data) is None:
                    errors.append((path, f"chaîne ne correspond pas au motif '{pattern}'"))

        # Nombres (booléens exclus)
        if isinstance(data, (int, float)) and not isinstance(data, bool):
            if "minimum" in schema and data < schema["minimum"]:
                errors.append((path, f"valeur {data} < minimum {schema['minimum']}"))
            if "maximum" in schema and data > schema["maximum"]:
                errors.append((path, f"valeur {data} > maximum {schema['maximum']}"))
            if "exclusiveMinimum" in schema and data <= schema["exclusiveMinimum"]:
                errors.append((path, f"valeur {data} <= exclusiveMinimum {schema['exclusiveMinimum']}"))
            if "exclusiveMaximum" in schema and data >= schema["exclusiveMaximum"]:
                errors.append((path, f"valeur {data} >= exclusiveMaximum {schema['exclusiveMaximum']}"))

        # Tableaux
        if isinstance(data, list):
            if "minItems" in schema and len(data) < int(schema["minItems"]):
                errors.append((path, f"tableau trop court ({len(data)} < minItems {schema['minItems']})"))
            if "maxItems" in schema and len(data) > int(schema["maxItems"]):
                errors.append((path, f"tableau trop long ({len(data)} > maxItems {schema['maxItems']})"))
            if schema.get("uniqueItems") is True:
                seen: List[Any] = []
                for i, item in enumerate(data):
                    if any(item == previous for previous in seen):
                        errors.append((index_path(path, i), "élément dupliqué (uniqueItems)"))
                    seen.append(item)
            items = schema.get("items")
            if isinstance(items, list):  # ancienne forme (tuples)
                for i, item in enumerate(data):
                    if i < len(items):
                        self._validate(item, items[i], index_path(path, i), depth + 1, errors)
            elif items is not None:
                for i, item in enumerate(data):
                    self._validate(item, items, index_path(path, i), depth + 1, errors)

        # Objets
        if isinstance(data, dict):
            properties = schema.get("properties", {})
            if not isinstance(properties, dict):
                self.schema_errors.append(f"{path} : 'properties' doit être un objet")
                properties = {}
            for key in schema.get("required", []):
                if key not in data:
                    errors.append((path, f"propriété requise manquante : '{key}'"))
            if "minProperties" in schema and len(data) < int(schema["minProperties"]):
                errors.append((path, f"trop peu de propriétés ({len(data)} < minProperties {schema['minProperties']})"))
            if "maxProperties" in schema and len(data) > int(schema["maxProperties"]):
                errors.append((path, f"trop de propriétés ({len(data)} > maxProperties {schema['maxProperties']})"))
            additional = schema.get("additionalProperties", True)
            for key, value in data.items():
                if key in properties:
                    self._validate(value, properties[key], child_path(path, key), depth + 1, errors)
                elif isinstance(additional, dict):
                    self._validate(value, additional, child_path(path, key), depth + 1, errors)
                elif additional is False:
                    errors.append((child_path(path, key), f"propriété non autorisée : '{key}'"))
            if "propertyNames" in schema:
                name_schema = schema["propertyNames"]
                for key in data:
                    name_errors: List[Tuple[str, str]] = []
                    self._validate(key, name_schema, child_path(path, key), depth + 1, name_errors)
                    for _unused, message in name_errors:
                        errors.append((child_path(path, key), f"nom de propriété invalide : {message}"))

        # Combinaisons
        for subschema in schema.get("allOf", []) if isinstance(schema.get("allOf"), list) else []:
            self._validate(data, subschema, path, depth + 1, errors)

        if "anyOf" in schema and isinstance(schema["anyOf"], list):
            variant_errors = [self._collect(data, variant, path) for variant in schema["anyOf"]]
            if all(variant for variant in variant_errors):
                details = " ; ".join(
                    f"variante {i + 1}: {variant[0][1]}" for i, variant in enumerate(variant_errors[:3])
                )
                errors.append((path, f"aucune variante anyOf ne correspond ({details})"))

        if "oneOf" in schema and isinstance(schema["oneOf"], list):
            variant_errors = [self._collect(data, variant, path) for variant in schema["oneOf"]]
            valid_count = sum(1 for variant in variant_errors if not variant)
            if valid_count != 1:
                errors.append((path, f"oneOf : {valid_count} variante(s) valide(s), 1 attendue"))

        if "not" in schema:
            if not self._collect(data, schema["not"], path):
                errors.append((path, "valeur interdite par 'not'"))

        if "if" in schema:
            condition_ok = not self._collect(data, schema["if"], path)
            branch = "then" if condition_ok else "else"
            if branch in schema:
                self._validate(data, schema[branch], path, depth + 1, errors)

    def _collect(self, data: Any, schema: Any, path: str) -> List[Tuple[str, str]]:
        """Valide dans un contexte isolé (anyOf/oneOf/if/not) sans polluer les erreurs."""
        isolated: List[Tuple[str, str]] = []
        self._validate(data, schema, path, 0, isolated)
        return isolated


# ---------------------------------------------------------------------------
# Auto-test : chaque mot-clé a au moins un cas valide et un cas invalide.
# ---------------------------------------------------------------------------

SELF_TESTS: List[Tuple[str, Any, Any, bool, Optional[str]]] = [
    ("type.object.ok", {"type": "object"}, {"a": 1}, True, None),
    ("type.object.ko", {"type": "object"}, [1], False, "$.type"),
    ("type.integer.bool.ko", {"type": "integer"}, True, False, "$.type"),
    ("type.number.integer.ok", {"type": "number"}, 3, True, None),
    ("required.ko", {"type": "object", "required": ["id"]}, {}, False, "$.id"),
    ("additionalProperties.false.ko", {"type": "object", "properties": {"a": {}}, "additionalProperties": False}, {"b": 1}, False, "$.b"),
    ("additionalProperties.schema.ko", {"type": "object", "additionalProperties": {"type": "integer"}}, {"x": "s"}, False, "$.x"),
    ("enum.ko", {"enum": ["a", "b"]}, "c", False, "$.enum"),
    ("const.ko", {"const": 3}, 4, False, "$.const"),
    ("string.pattern.ko", {"type": "string", "pattern": "^\\d{4}$"}, "12a4", False, "$.pattern"),
    ("string.length.ko", {"type": "string", "minLength": 3, "maxLength": 4}, "ab", False, "$.minLength"),
    ("number.range.ko", {"type": "integer", "minimum": 2, "maximum": 6}, 7, False, "$.maximum"),
    ("array.items.ko", {"type": "array", "items": {"type": "integer"}}, [1, "x"], False, "$[1].type"),
    ("array.minItems.ko", {"type": "array", "minItems": 2}, [1], False, "$.minItems"),
    ("array.maxItems.ko", {"type": "array", "maxItems": 1}, [1, 2], False, "$.maxItems"),
    (
        "ref.defs.ok",
        {"$defs": {"point": {"type": "object", "required": ["x"]}}, "properties": {"p": {"$ref": "#/$defs/point"}}},
        {"p": {"x": 1}},
        True,
        None,
    ),
    (
        "ref.defs.ko",
        {"$defs": {"point": {"type": "object", "required": ["x"]}}, "properties": {"p": {"$ref": "#/$defs/point"}}},
        {"p": {}},
        False,
        "$.p.x",
    ),
    (
        "ref.self.recursive.ko",
        {"type": "object", "properties": {"child": {"$ref": "#"}}, "required": ["name"]},
        {"name": "a", "child": {"name": "b", "child": {}}},
        False,
        "$.child.child.name",
    ),
    ("allOf.ko", {"allOf": [{"type": "object"}, {"required": ["a"]}]}, {}, False, "$.a"),
    (
        "if.then.ko",
        {"if": {"properties": {"kind": {"const": "x"}}}, "then": {"required": ["v"]}},
        {"kind": "x"},
        False,
        "$.v",
    ),
    (
        "if.else.ok",
        {"if": {"properties": {"kind": {"const": "x"}}, "required": ["kind"]}, "then": {"required": ["v"]}, "else": {"required": ["w"]}},
        {"kind": "y", "w": 1},
        True,
        None,
    ),
    ("oneOf.ko", {"oneOf": [{"type": "string"}, {"type": "integer"}]}, 1.5, False, "$.oneOf"),
    ("anyOf.ok", {"anyOf": [{"type": "string"}, {"type": "integer"}]}, 2, True, None),
    ("propertyNames.ko", {"type": "object", "propertyNames": {"pattern": "^[a-z]+$"}}, {"Bad": 1}, False, "$.Bad"),
    ("uniqueItems.ko", {"type": "array", "uniqueItems": True}, [1, 1], False, "$[1]"),
    ("boolean.false.ko", False, "anything", False, "$"),
    ("boolean.true.ok", True, "anything", True, None),
]


def run_self_test(verbose: bool = False) -> int:
    """Exécute les cas internes ; retourne le nombre d'échecs."""
    failures = 0
    for name, schema, data, expected_valid, expected_path in SELF_TESTS:
        validator = SchemaValidator(schema, f"self-test:{name}")
        errors = validator.validate(data)
        valid = not errors
        ok = valid == expected_valid
        if ok and expected_path is not None:
            ok = any(path.startswith(expected_path) or expected_path.startswith(path) for path, _ in errors)
        if not ok:
            failures += 1
            print(f"  auto-test:FAIL {name} (attendu valide={expected_valid}, chemin≈{expected_path}, "
                  f"obtenu {len(errors)} erreur(s) : {errors[:3]})", file=sys.stderr)
        elif verbose:
            print(f"  auto-test:ok {name}")
    return failures


# ---------------------------------------------------------------------------
# Chargement et validation des données réelles
# ---------------------------------------------------------------------------


def load_json(path: pathlib.Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def walk_schema_keywords(node: Any, unsupported: set, trail: str = "$") -> None:
    """Parcourt un schéma et collecte les mots-clés non reconnus (hors annotations)."""
    if isinstance(node, list):
        for i, item in enumerate(node):
            walk_schema_keywords(item, unsupported, f"{trail}[{i}]")
        return
    if not isinstance(node, dict):
        return
    for key, value in node.items():
        if key not in ANNOTATION_KEYWORDS and key not in SUPPORTED_KEYWORDS:
            unsupported.add(key)
        if key in ("properties", "$defs") and isinstance(value, dict):
            for sub in value.values():
                walk_schema_keywords(sub, unsupported, f"{trail}.{key}")
        elif key in ("additionalProperties", "items", "propertyNames", "not", "if", "then", "else"):
            walk_schema_keywords(value, unsupported, f"{trail}.{key}")
        elif key in ("allOf", "anyOf", "oneOf") and isinstance(value, list):
            for sub in value:
                walk_schema_keywords(sub, unsupported, f"{trail}.{key}")


def load_schemas(root: pathlib.Path) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    """Charge les 8 schémas, vérifie qu'ils sont lisibles et que leurs $ref se résolvent."""
    schemas: Dict[str, Any] = {}
    checks: Dict[str, Any] = {"count": 0, "unresolved_refs": [], "unsupported_keywords": []}
    for name, _mapping in ((m["schema"], m) for m in MAPPINGS):
        schema_path = root / SCHEMAS_DIR / f"{name}.json"
        if not schema_path.exists():
            checks["unresolved_refs"].append(f"{SCHEMAS_DIR}/{name}.json : fichier absent")
            continue
        try:
            schema = load_json(schema_path)
        except json.JSONDecodeError as exc:
            checks["unresolved_refs"].append(f"{SCHEMAS_DIR}/{name}.json : JSON invalide ({exc})")
            continue
        validator = SchemaValidator(schema, f"{SCHEMAS_DIR}/{name}.json")
        validator._check_refs(schema)
        walk_schema_keywords(schema, validator.unsupported)
        if validator.schema_errors:
            checks["unresolved_refs"].extend(f"{name}: {msg}" for msg in validator.schema_errors)
        schemas[name] = validator
    checks["count"] = len(schemas)
    unsupported = set()
    for validator in schemas.values():
        unsupported |= validator.unsupported
    checks["unsupported_keywords"] = sorted(unsupported)
    return schemas, checks


def mirror_of(root: pathlib.Path, rel_path: str) -> Optional[str]:
    """Retourne le chemin canonique d'un miroir identique (data/ → game/data/) ou None.

    Seul le dossier racine `data/` est marqué comme miroir : `game/data/` est la
    copie canonique lue par le client Godot (`res://data`), pour éviter de
    compter deux fois le même couple.
    """
    if not rel_path.startswith("data/"):
        return None
    other = "game/" + rel_path
    other_path = root / other
    path = root / rel_path
    if not other_path.exists():
        return None
    try:
        if sha256(path) == sha256(other_path):
            return other
    except OSError:
        return None
    return None


def discover_data_files(root: pathlib.Path, globs: Sequence[str]) -> List[pathlib.Path]:
    found: List[pathlib.Path] = []
    seen = set()
    for pattern in globs:
        for path in sorted(root.glob(pattern)):
            resolved = path.resolve()
            if resolved in seen or not path.is_file():
                continue
            seen.add(resolved)
            found.append(path)
    return found


def validate_pair(
    root: pathlib.Path,
    schema_name: str,
    schema_path: pathlib.Path,
    data_path: pathlib.Path,
    mode: str,
) -> Dict[str, Any]:
    schema = load_json(schema_path)
    validator = SchemaValidator(schema, str(schema_path))
    data = load_json(data_path)
    errors: List[Tuple[str, str]] = []
    items_validated = 0
    if mode == "array-items":
        if not isinstance(data, list):
            errors.append(("$", f"mode array-items : tableau attendu, obtenu '{json_type(data)}'"))
        else:
            items_validated = len(data)
            for index, item in enumerate(data):
                for path_suffix, message in validator.validate(item):
                    errors.append((f"$[{index}]" + path_suffix[1:], message))
    else:
        errors = validator.validate(data)
    rel = data_path.relative_to(root).as_posix()
    mirror = mirror_of(root, rel)
    return {
        "schema": schema_name,
        "path": rel,
        "mode": mode,
        "items": items_validated,
        "errors": [{"path": path, "message": message} for path, message in errors],
        "error_count": len(errors),
        "mirror_of": mirror,
        "schema_errors": list(validator.schema_errors),
    }


def aggregate_messages(files: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Agrège les messages d'erreur (mêmes causes regroupées) pour le rapport."""
    buckets: Dict[str, Dict[str, Any]] = {}
    for file_report in files:
        for error in file_report["errors"]:
            bucket = buckets.setdefault(
                error["message"],
                {"message": error["message"], "count": 0, "example": {"path": error["path"], "file": file_report["path"]}},
            )
            bucket["count"] += 1
    return sorted(buckets.values(), key=lambda item: item["count"], reverse=True)


def collect_uncovered(root: pathlib.Path, mapped_relative: set) -> List[Dict[str, str]]:
    uncovered: List[Dict[str, str]] = []
    candidates: List[pathlib.Path] = []
    for base in (root / "data", root / "game" / "data"):
        if base.exists():
            candidates.extend(sorted(base.rglob("*.json")))
    for path in candidates:
        rel = path.relative_to(root).as_posix()
        if rel.startswith("data/schemas/") or rel.startswith("game/data/schemas/"):
            continue  # ce sont des schémas, pas des données
        if rel in mapped_relative:
            continue
        reason = UNCOVERED_REASONS.get(rel)
        if reason is None:
            if rel.startswith("data/sessions/") or rel.startswith("game/data/sessions/"):
                reason = "échantillon runtime (SessionRecord {state, scenario}), ne correspond à aucun schéma"
            else:
                reason = "aucun schéma de correspondance déclaré"
        uncovered.append({"path": rel, "reason": reason})
    return uncovered


def build_report(root: pathlib.Path, only: Optional[set]) -> Dict[str, Any]:
    schemas, schema_checks = load_schemas(root)
    report: Dict[str, Any] = {
        "root": str(root),
        "schemas_dir": SCHEMAS_DIR,
        "schema_checks": schema_checks,
        "mappings": [],
        "schemas": {},
        "totals": {
            "schemas_with_data": 0,
            "files": 0,
            "errors": 0,
            "mirrors": 0,
            "files_unique": 0,
            "errors_unique": 0,
        },
        "uncovered": [],
    }
    mapped_relative: set = set()
    # Tous les fichiers couverts par AU MOINS une correspondance (même filtrée par
    # --only) restent « couverts » pour la liste des fichiers hors contrat.
    for mapping in MAPPINGS:
        for data_path in discover_data_files(root, mapping["globs"]):
            mapped_relative.add(data_path.relative_to(root).as_posix())
    for mapping in MAPPINGS:
        name = mapping["schema"]
        if only and name not in only:
            continue
        schema_path = root / SCHEMAS_DIR / f"{name}.json"
        entry = {
            "schema": name,
            "schema_path": f"{SCHEMAS_DIR}/{name}.json",
            "mode": mapping["mode"],
            "globs": list(mapping["globs"]),
            "note": mapping["note"],
            "data_files": 0,
            "files_mirror": 0,
            "errors": 0,
            "errors_mirror": 0,
            "files": [],
            "top_messages": [],
        }
        # Le schéma peut manquer : on le signale au lieu de planter.
        if not schema_path.exists():
            entry["schema_error"] = "schéma absent"
            report["mappings"].append(entry)
            report["schemas"][name] = entry
            continue
        for data_path in discover_data_files(root, mapping["globs"]):
            rel = data_path.relative_to(root).as_posix()
            mapped_relative.add(rel)
            file_report = validate_pair(root, name, schema_path, data_path, mapping["mode"])
            entry["files"].append(file_report)
            entry["data_files"] += 1
            entry["errors"] += file_report["error_count"]
            if file_report["mirror_of"]:
                report["totals"]["mirrors"] += 1
                entry["files_mirror"] += 1
                entry["errors_mirror"] += file_report["error_count"]
        entry["top_messages"] = aggregate_messages(entry["files"])
        report["mappings"].append(entry)
        report["schemas"][name] = entry
        if entry["data_files"] > 0:
            report["totals"]["schemas_with_data"] += 1
        if entry["errors"]:
            report["totals"]["errors"] += entry["errors"]
        report["totals"]["files"] += entry["data_files"]
    report["uncovered"] = collect_uncovered(root, mapped_relative)
    totals = report["totals"]
    totals["files_unique"] = totals["files"] - totals["mirrors"]
    totals["errors_unique"] = totals["errors"] - sum(
        entry["errors_mirror"] for entry in report["schemas"].values()
    )
    return report


# ---------------------------------------------------------------------------
# Sortie texte
# ---------------------------------------------------------------------------


def print_text_report(report: Dict[str, Any], max_per_file: int) -> None:
    checks = report["schema_checks"]
    print("== validate_data.py — validateur JSON Schema (sans dépendance) ==")
    print(f"Schémas chargés : {checks['count']}/8 ; $ref non résolus : {len(checks['unresolved_refs'])}")
    for message in checks["unresolved_refs"]:
        print(f"  SCHÉMA: {message}")
    if checks["unsupported_keywords"]:
        print(f"Mots-clés non supportés rencontrés : {', '.join(checks['unsupported_keywords'])}")
    print()
    for mapping in report["mappings"]:
        name = mapping["schema"]
        status = (
            "non couvert (aucune donnée versionnée)"
            if mapping["data_files"] == 0
            else f"{mapping['data_files']} fichier(s), {mapping['errors']} erreur(s)"
        )
        print(f"[{name}] {mapping['schema_path']} — {status}")
        for file_report in mapping["files"]:
            mirror = " (miroir)" if file_report["mirror_of"] else ""
            print(f"  {file_report['path']}{mirror} : {file_report['error_count']} erreur(s)")
            shown = 0
            for error in file_report["errors"]:
                if max_per_file and shown >= max_per_file:
                    print(f"    … {file_report['error_count'] - shown} autre(s) erreur(s) (--max-per-file 0 pour tout)")
                    break
                print(f"    {error['path']}: {error['message']}")
                shown += 1
        if mapping["data_files"] == 0:
            print(f"  note: {mapping['note']}")
        print()
    totals = report["totals"]
    print(
        f"Total : {totals['files']} fichier(s) validé(s) ({totals['mirrors']} miroir(s) identique(s), "
        f"{totals['files_unique']} unique(s)), {totals['errors']} erreur(s) "
        f"({totals['errors_unique']} hors miroirs)."
    )
    print(f"Schémas avec données : {totals['schemas_with_data']}/8.")
    if report["uncovered"]:
        print(f"Fichiers JSON hors contrat ({len(report['uncovered'])}) :")
        for item in report["uncovered"]:
            print(f"  {item['path']} — {item['reason']}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def default_root() -> pathlib.Path:
    return pathlib.Path(__file__).resolve().parents[2]


def write_json_file(destination: str, payload: Any) -> pathlib.Path:
    out = pathlib.Path(destination)
    if not out.is_absolute():
        out = pathlib.Path.cwd() / out
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return out


def main(argv: Optional[Sequence[str]] = None) -> int:
    # Sortie UTF-8 déterministe (accents/messages), même sur console Windows cp1252.
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[attr-defined]
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(
        description="Validateur JSON Schema minimal sans dépendance + rapport de dérive data/schemas.",
    )
    parser.add_argument("--root", default=str(default_root()), help="racine du dépôt (défaut : déduite du script)")
    parser.add_argument("--json", action="store_true", help="sortie JSON machine (stdout)")
    parser.add_argument("--json-output", help="écrit le rapport JSON dans ce fichier (UTF-8)")
    parser.add_argument("--list", action="store_true", help="affiche seulement la matrice schéma↔données")
    parser.add_argument("--only", default="", help="liste de schémas à valider (ex. scenario,map)")
    parser.add_argument("--max-per-file", type=int, default=10, help="erreurs affichées par fichier en mode texte (0 = toutes)")
    parser.add_argument("--schema", help="validation ad hoc : chemin du schéma")
    parser.add_argument("--data", help="validation ad hoc : chemin du fichier de données")
    parser.add_argument("--mode", choices=("object", "array-items"), default="object", help="mode de validation ad hoc")
    parser.add_argument("--skip-self-test", action="store_true", help="ne pas exécuter l'auto-test intégré")
    args = parser.parse_args(argv)

    root = pathlib.Path(args.root).resolve()
    if not (root / SCHEMAS_DIR).is_dir():
        print(f"validate_data.py: erreur — {SCHEMAS_DIR} introuvable sous {root}", file=sys.stderr)
        return 1

    self_test_failures = 0
    if not args.skip_self_test:
        self_test_failures = run_self_test()
        if self_test_failures:
            print(
                f"validate_data.py: auto-test EN ÉCHEC ({self_test_failures}/{len(SELF_TESTS)})",
                file=sys.stderr,
            )
            return 1
        if not args.json and not args.list:
            print(f"auto-test : {len(SELF_TESTS)}/{len(SELF_TESTS)} cas OK")

    if args.schema or args.data:
        if not (args.schema and args.data):
            print("validate_data.py: --schema et --data doivent être fournis ensemble", file=sys.stderr)
            return 1
        schema_path = (root / args.schema) if not pathlib.Path(args.schema).is_absolute() else pathlib.Path(args.schema)
        data_path = (root / args.data) if not pathlib.Path(args.data).is_absolute() else pathlib.Path(args.data)
        result = validate_pair(root, pathlib.Path(schema_path).stem, schema_path, data_path, args.mode)
        if args.json_output:
            written = write_json_file(args.json_output, result)
            print(f"rapport JSON écrit : {written}")
        if args.json:
            print(json.dumps(result, ensure_ascii=False, indent=2))
        elif not args.json_output:
            print(f"{result['path']} vs {result['schema']} : {result['error_count']} erreur(s)")
            for error in result["errors"]:
                print(f"  {error['path']}: {error['message']}")
        return 0 if result["error_count"] == 0 else 1

    only = {item.strip() for item in args.only.split(",") if item.strip()} or None
    report = build_report(root, only)
    if args.list:
        for mapping in report["mappings"]:
            scope = ", ".join(mapping["globs"]) if "globs" in mapping else "(données découvertes)"
            print(f"{mapping['schema']:14s} {mapping['mode']:11s} {scope}")
        for item in report["uncovered"]:
            print(f"{'(non couvert)':14s} {'':11s} {item['path']} — {item['reason']}")
        return 0
    report["self_test"] = {
        "cases": len(SELF_TESTS),
        "failures": self_test_failures,
    }
    if args.json_output:
        written = write_json_file(args.json_output, report)
        print(f"rapport JSON écrit : {written}")
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        print_text_report(report, args.max_per_file)
        print()
        print("Commande reproductible : python tools/refactor/validate_data.py")
        print(
            "Code retour : "
            + ("0 (aucune dérive)" if report["totals"]["errors"] == 0 else "1 (dérive détectée)")
        )
    return 0 if report["totals"]["errors"] == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
