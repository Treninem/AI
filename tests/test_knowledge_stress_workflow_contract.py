from __future__ import annotations

from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github" / "workflows" / "knowledge-performance.yml"


def job_section(text: str, job: str, next_job: str | None = None) -> str:
    start = text.index(f"  {job}:\n")
    if next_job is None:
        return text[start:]
    end = text.index(f"  {next_job}:\n", start + 1)
    return text[start:end]


class KnowledgeStressWorkflowContractTests(unittest.TestCase):
    def test_large_push_runs_full_n_2n_4n_scaling_suite(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        section = job_section(text, "large-linux-push", "manual-large")

        self.assertIn("--profile stress", section)
        self.assertIn("run_memory_scaling.py --godot ./godot --counts 250,500,1000", section)
        self.assertIn("run_search_scaling.py --godot ./godot --sizes-mb 4,8,16", section)
        self.assertIn("run_registry_scaling.py --godot ./godot --counts 32,64,128", section)
        self.assertIn("artifacts/knowledge-performance/linux-stress-memory-scaling.json", section)
        self.assertIn("artifacts/knowledge-performance/linux-stress-search-scaling.json", section)
        self.assertIn("artifacts/knowledge-performance/linux-stress-registry-scaling.json", section)

        validator = section.split("- name: Enforce large-profile blockers", 1)[1]
        for report in (
            "linux-stress.json",
            "linux-stress-memory-scaling.json",
            "linux-stress-search-scaling.json",
            "linux-stress-registry-scaling.json",
        ):
            self.assertIn(report, validator)

    def test_manual_standard_and_stress_select_matching_scaling_ranges(self) -> None:
        text = WORKFLOW.read_text(encoding="utf-8")
        section = job_section(text, "manual-large")

        self.assertIn('memory_counts="125,250,500"', section)
        self.assertIn('memory_counts="250,500,1000"', section)
        self.assertIn('search_sizes="1,2,4"', section)
        self.assertIn('search_sizes="4,8,16"', section)
        self.assertIn('registry_counts="16,32,64"', section)
        self.assertIn('registry_counts="32,64,128"', section)
        self.assertIn("run_memory_scaling.py", section)
        self.assertIn("run_search_scaling.py", section)
        self.assertIn("run_registry_scaling.py", section)

        validator = section.split("- name: Enforce large-profile relative performance blockers", 1)[1]
        for report in (
            "linux-${{ inputs.profile }}.json",
            "linux-${{ inputs.profile }}-memory-scaling.json",
            "linux-${{ inputs.profile }}-search-scaling.json",
            "linux-${{ inputs.profile }}-registry-scaling.json",
        ):
            self.assertIn(report, validator)


if __name__ == "__main__":
    unittest.main()
