"""Convert the best checkpoint to Core ML and record everything the app must agree with.

Writes the .mlpackage, model_fixtures.json (Core ML's own output on the pipeline fixtures, replayed
by an XCTest in the simulator), catalog.json and model_card.json, then checks the converted model
against PyTorch on held-out bitmaps.

Usage: python -m doodledex_ml.convert
"""

import base64
import json
import shutil
from pathlib import Path

import coremltools as ct
import numpy as np
import torch

from doodledex_ml.calibration import ConfidenceTable
from doodledex_ml.classes import CHAPTERS, CLASSES
from doodledex_ml.data import DATA_DIR, REPO_ROOT
from doodledex_ml.evaluate import load_network, probabilities
from doodledex_ml.fixtures import PIPELINE_FIXTURES
from doodledex_ml.model import DeployedDoodleNet
from doodledex_ml.train import load_split

APP_RESOURCES = REPO_ROOT / "DoodleDex" / "Resources"
MODEL_PATH = APP_RESOURCES / "DoodleClassifier.mlpackage"
MODEL_FIXTURES = PIPELINE_FIXTURES.parent / "model_fixtures.json"
ATTRIBUTION = "Trained on Google's Quick, Draw! dataset (CC BY 4.0)"


def convert() -> ct.models.MLModel:
    wrapped = DeployedDoodleNet(load_network(torch.device("cpu"))).eval()
    example = torch.zeros(1, 1, 28, 28)
    traced = torch.jit.trace(wrapped, example)
    model = ct.convert(
        traced,
        inputs=[ct.TensorType(name="pixels", shape=example.shape, dtype=np.float32)],
        classifier_config=ct.ClassifierConfig(CLASSES),
        convert_to="mlprogram",
        minimum_deployment_target=ct.target.iOS17,
        compute_precision=ct.precision.FLOAT32,
    )
    model.short_description = "Sketch classifier for 100 Quick, Draw! categories"
    model.author = ATTRIBUTION
    model.license = "Model MIT, training data CC BY 4.0"
    model.input_description["pixels"] = "28x28 raw pixels, 0-255, ink high, row-major"
    return model


def predict(model: ct.models.MLModel, image: np.ndarray) -> dict[str, float]:
    array = image.astype(np.float32).reshape(1, 1, 28, 28)
    return next(v for v in model.predict({"pixels": array}).values() if isinstance(v, dict))


def write_model_fixtures(model: ct.models.MLModel) -> int:
    cases = json.loads(PIPELINE_FIXTURES.read_text())["cases"]
    shipped = json.loads((APP_RESOURCES / "confidence_table.json").read_text())
    table = ConfidenceTable(np.array(shipped["probabilities"]))
    rows = []
    for case in cases:
        pixels = np.frombuffer(base64.b64decode(case["pixels"]), dtype=np.uint8)
        ranked = sorted(predict(model, pixels).items(), key=lambda item: -item[1])[:5]
        strokes = len(case["point_counts"])
        calibrated = table.lookup(np.array([ranked[0][1]]), np.array([strokes]))[0]
        rows.append(
            {
                "id": case["id"],
                "top": [{"label": name, "probability": float(p)} for name, p in ranked],
                "strokes": strokes,
                "calibrated": float(calibrated),
            }
        )
    MODEL_FIXTURES.write_text(json.dumps({"schema": 1, "cases": rows}, indent=0) + "\n")
    return len(rows)


def check_against_pytorch(model: ct.models.MLModel, samples: int = 4000) -> dict:
    images, labels = load_split("test")
    rows = torch.randperm(images.shape[0], generator=torch.Generator().manual_seed(11))[:samples]
    images, labels = images[rows].numpy(), labels[rows].numpy()
    torch_probabilities = probabilities(
        load_network(torch.device("cpu")), images, torch.device("cpu")
    )
    core_ml = np.zeros_like(torch_probabilities)
    for row, image in enumerate(images):
        scores = predict(model, image)
        core_ml[row] = [scores[name] for name in CLASSES]
    return {
        "samples": samples,
        "top1_agreement": float((core_ml.argmax(1) == torch_probabilities.argmax(1)).mean()),
        "max_probability_difference": float(np.abs(core_ml - torch_probabilities).max()),
        "core_ml_top1": round(float((core_ml.argmax(1) == labels).mean()), 4),
        "pytorch_top1": round(float((torch_probabilities.argmax(1) == labels).mean()), 4),
    }


def package_megabytes(path: Path) -> float:
    return sum(item.stat().st_size for item in path.rglob("*") if item.is_file()) / 1048576


def main() -> None:
    APP_RESOURCES.mkdir(parents=True, exist_ok=True)
    model = convert()
    temporary = DATA_DIR / "DoodleClassifier.mlpackage"
    shutil.rmtree(temporary, ignore_errors=True)
    model.save(str(temporary))
    shutil.rmtree(MODEL_PATH, ignore_errors=True)
    shutil.copytree(temporary, MODEL_PATH)
    loaded = ct.models.MLModel(str(MODEL_PATH), compute_units=ct.ComputeUnit.CPU_ONLY)

    check = check_against_pytorch(loaded)
    check["model_megabytes"] = round(package_megabytes(MODEL_PATH), 3)
    check["fixture_cases"] = write_model_fixtures(loaded)
    (REPO_ROOT / "results" / "conversion_check.json").write_text(json.dumps(check, indent=2) + "\n")

    catalog = {"chapters": [{"name": k, "categories": sorted(v)} for k, v in CHAPTERS.items()]}
    (APP_RESOURCES / "catalog.json").write_text(json.dumps(catalog, indent=2) + "\n")

    metrics = json.loads((REPO_ROOT / "results" / "test_metrics.json").read_text())
    card = {
        "attribution": ATTRIBUTION,
        "dataset_url": "https://github.com/googlecreativelab/quickdraw-dataset",
        "classes": metrics["classes"],
        "test_images": metrics["images"],
        "test_top1": metrics["top1"],
        "test_top5": metrics["top5"],
        "model_megabytes": check["model_megabytes"],
    }
    (APP_RESOURCES / "model_card.json").write_text(json.dumps(card, indent=2) + "\n")
    print(json.dumps(check, indent=2))


if __name__ == "__main__":
    main()
