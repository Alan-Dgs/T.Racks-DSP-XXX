"""Guided DSP protocol capture helper.

Small Windows/Tkinter utility for capturing short Wireshark/dumpcap scenarios
while the official t.racks DSP editor is operated by hand.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from tkinter import (
    BOTH,
    END,
    LEFT,
    RIGHT,
    Button,
    Entry,
    Frame,
    Label,
    Listbox,
    OptionMenu,
    Scrollbar,
    StringVar,
    Text,
    Tk,
    filedialog,
    messagebox,
)


ROOT = Path(__file__).resolve().parents[2]
SCENARIO_DIR = Path(__file__).resolve().parent / "scenarios"
WIRESHARK_DIR = Path(r"C:\Program Files\Wireshark")
DUMPCAP = WIRESHARK_DIR / "dumpcap.exe"


@dataclass(frozen=True)
class Scenario:
    order: int
    key: str
    title: str
    file_stem: str
    steps: tuple[str, ...]


FALLBACK_SCENARIOS: tuple[Scenario, ...] = (
    Scenario(
        1,
        "phase",
        "Phase input/output",
        "001_phase_input_output",
        (
            "Dans l'editeur officiel, ouvre l'onglet Gain.",
            "Passe InA de Normal a Inverse, puis clique Action faite.",
            "Repasse InA de Inverse a Normal, puis clique Action faite.",
            "Passe Out1 de Normal a Inverse, puis clique Action faite.",
            "Repasse Out1 de Inverse a Normal, puis clique Action faite.",
        ),
    ),
    Scenario(
        2,
        "matrix_attenuation",
        "Matrix attenuation",
        "002_matrix_attenuation_out1_ina",
        (
            "Ouvre l'onglet Matrix.",
            "Sur Out1/InA, regle le gain a +0.0 dB, puis clique Action faite.",
            "Sur Out1/InA, regle le gain a -6.0 dB, puis clique Action faite.",
            "Sur Out1/InA, regle le gain a -20.0 dB, puis clique Action faite.",
            "Sur Out1/InA, regle le gain a -60.0 dB, puis clique Action faite.",
        ),
    ),
    Scenario(
        3,
        "gate",
        "Gate InA",
        "003_gate_ina_threshold_attack_hold_release",
        (
            "Ouvre l'onglet Gate.",
            "Sur InA, mets Threshold a -40.0 dB, puis clique Action faite.",
            "Sur InA, mets Attack a 10 ms, puis clique Action faite.",
            "Sur InA, mets Hold a 250 ms, puis clique Action faite.",
            "Sur InA, mets Release a 750 ms, puis clique Action faite.",
        ),
    ),
    Scenario(
        4,
        "comp",
        "Compressor Out1",
        "004_comp_out1_threshold_ratio_knee_attack_release",
        (
            "Ouvre l'onglet Comp.",
            "Sur Out1, mets Threshold a -20.0 dB, puis clique Action faite.",
            "Sur Out1, mets Ratio a 1:4.0, puis clique Action faite.",
            "Sur Out1, mets Knee a 6 dB, puis clique Action faite.",
            "Sur Out1, mets Attack a 25 ms, puis clique Action faite.",
            "Sur Out1, mets Release a 800 ms, puis clique Action faite.",
        ),
    ),
    Scenario(
        5,
        "limit",
        "Limiter Out1",
        "005_limit_out1_threshold_attack_release",
        (
            "Ouvre l'onglet Limit.",
            "Sur Out1, mets Threshold a -10.0 dB, puis clique Action faite.",
            "Sur Out1, mets Attack a 20 ms, puis clique Action faite.",
            "Sur Out1, mets Release a 500 ms, puis clique Action faite.",
        ),
    ),
    Scenario(
        6,
        "delay",
        "Delay input/output units",
        "006_delay_ina_out1_ms_m_ft",
        (
            "Ouvre l'onglet Delay.",
            "En unite ms, mets InA a 1.000 ms, puis clique Action faite.",
            "En unite ms, mets Out1 a 10.000 ms, puis clique Action faite.",
            "Passe l'unite en m, puis clique Action faite.",
            "Passe l'unite en ft, puis clique Action faite.",
        ),
    ),
    Scenario(
        7,
        "peq_hpf_lpf",
        "PEQ + HPF/LPF",
        "007_peq_hpf_lpf_ina_out1",
        (
            "Ouvre l'onglet InA.",
            "Band 1: mets Gain a +3.0 dB, puis clique Action faite.",
            "Band 1: change Type en Low Shelf, puis clique Action faite.",
            "Band 1: active Bypass, puis clique Action faite.",
            "HighPass: mets 315.0 Hz et slope BW -24, puis clique Action faite.",
            "LowPass: mets 20.16 kHz et slope LK -48/LR -48, puis clique Action faite.",
            "Ouvre l'onglet Out1.",
            "Band 9: mets Gain a -3.0 dB, puis clique Action faite.",
        ),
    ),
    Scenario(
        8,
        "geq_bypass_reset",
        "GEQ bypass/reset",
        "008_geq_bypass_reset_ina",
        (
            "Ouvre l'onglet GEQ.",
            "Sur InA, mets 1 kHz a +3.0 dB, puis clique Action faite.",
            "Clique EQ Bypass, puis clique Action faite.",
            "Clique EQ Reset, confirme OK, puis clique Action faite.",
        ),
    ),
    Scenario(
        9,
        "test_tone",
        "Test Tone",
        "009_test_tone_sources_sine",
        (
            "Ouvre Test Tone.",
            "Selectionne Analog Input, puis clique Action faite.",
            "Selectionne Pink Noise, puis clique Action faite.",
            "Selectionne White Noise, puis clique Action faite.",
            "Selectionne Sine Wave 20 Hz, puis clique Action faite.",
            "Selectionne Sine Wave 1 kHz, puis clique Action faite.",
            "Selectionne Sine Wave 20 kHz, puis clique Action faite.",
        ),
    ),
    Scenario(
        10,
        "channel_name",
        "Channel Name",
        "010_channel_name_8chars",
        (
            "Ouvre Channel Name.",
            "Renomme InA en 12345678, puis clique Set et Action faite.",
            "Renomme Out1 en 12345678, puis clique Set et Action faite.",
            "Remets InA et Out1 a leur nom initial, puis clique Action faite.",
        ),
    ),
    Scenario(
        11,
        "link_copy",
        "Link and Copy",
        "011_link_copy_in_out",
        (
            "Ouvre Link.",
            "Lie InA avec InB, clique Set, puis clique Action faite.",
            "Change un parametre simple sur InA pour verifier copie vers InB, puis clique Action faite.",
            "Ouvre Copy.",
            "Copie InA vers InB, puis clique Action faite.",
            "Copie Out1 vers Out2, puis clique Action faite.",
        ),
    ),
    Scenario(
        12,
        "file_setting_lock",
        "File / Setting ID-IP / Lock",
        "012_file_setting_lock_low_priority",
        (
            "Ouvre File et clique Open sans choisir de fichier, puis clique Action faite.",
            "Ouvre File et note les options visibles, puis clique Action faite.",
            "Ouvre Setting ID/IP sans modifier, puis clique Action faite.",
            "Ouvre Lock sans valider de changement, puis clique Action faite.",
        ),
    ),
)


class CaptureHelperApp:
    def __init__(self, root: Tk) -> None:
        self.root = root
        self.root.title("DSP capture helper")
        self.root.geometry("1020x720")

        self.capture_process: subprocess.Popen | None = None
        self.active_scenario: Scenario | None = None
        self.active_step_index = 0
        self.active_pcap: Path | None = None
        self.active_json: Path | None = None
        self.event_log: list[dict] = []

        self.model = StringVar(value="DSP408")
        self.language = StringVar(value="fr")
        self.ip = StringVar(value="192.168.0.99")
        self.port = StringVar(value="9761")
        self.interface = StringVar(value="")
        self.output_dir = StringVar(value=str(self.default_output_dir()))
        self.status = StringVar(value="Pret.")
        self.capture_name = StringVar(value="")
        self.scenarios = self.load_scenarios()

        self.interfaces = self.load_interfaces()
        if self.interfaces:
            self.interface.set(self.interfaces[0])

        self.build_ui()
        self.refresh_scenario_text()
        self.root.protocol("WM_DELETE_WINDOW", self.on_close)

    def default_output_dir(self) -> Path:
        today = datetime.now().strftime("%Y-%m-%d")
        return ROOT / "captures" / self.model.get() / today

    def load_scenarios(self) -> list[Scenario]:
        path = SCENARIO_DIR / f"{self.model.get().lower()}.{self.language.get()}.json"
        if not path.exists():
            return list(FALLBACK_SCENARIOS)
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            scenarios = []
            for item in data.get("scenarios", []):
                scenarios.append(
                    Scenario(
                        order=int(item["order"]),
                        key=str(item["key"]),
                        title=str(item["title"]),
                        file_stem=str(item["file_stem"]),
                        steps=tuple(str(step) for step in item["steps"]),
                    )
                )
            return scenarios or list(FALLBACK_SCENARIOS)
        except Exception as exc:
            self.status.set(f"Scenario JSON unreadable: {path.name}: {exc}")
            return list(FALLBACK_SCENARIOS)

    def load_interfaces(self) -> list[str]:
        if not DUMPCAP.exists():
            return []
        try:
            result = subprocess.run(
                [str(DUMPCAP), "-D"],
                check=False,
                capture_output=True,
                text=True,
                timeout=8,
            )
        except Exception:
            return []

        interfaces: list[str] = []
        for line in result.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            match = re.match(r"^(\d+)\.\s+(.+)$", line)
            if match:
                interfaces.append(f"{match.group(1)} - {match.group(2)}")
        return interfaces

    def build_ui(self) -> None:
        top = Frame(self.root)
        top.pack(fill="x", padx=10, pady=8)

        self.add_labeled_option(
            top,
            "Modele",
            self.model,
            ["DSP408", "DSP206", "DSP204"],
            self.on_settings_changed,
        )
        self.add_labeled_option(
            top,
            "Langue",
            self.language,
            ["fr", "en"],
            self.on_settings_changed,
        )
        self.add_labeled_entry(top, "IP DSP", self.ip, width=15)
        self.add_labeled_entry(top, "Port", self.port, width=7)

        iface_values = self.interfaces or ["MANUEL - dumpcap indisponible"]
        self.add_labeled_option(top, "Interface", self.interface, iface_values)

        dir_frame = Frame(self.root)
        dir_frame.pack(fill="x", padx=10, pady=(0, 8))
        Label(dir_frame, text="Dossier").pack(side=LEFT)
        Entry(dir_frame, textvariable=self.output_dir).pack(side=LEFT, fill="x", expand=True, padx=6)
        Button(dir_frame, text="Choisir", command=self.choose_output_dir).pack(side=LEFT)
        Button(dir_frame, text="Ouvrir dossier", command=self.open_output_dir).pack(side=LEFT, padx=(6, 0))

        main = Frame(self.root)
        main.pack(fill=BOTH, expand=True, padx=10, pady=4)

        left = Frame(main)
        left.pack(side=LEFT, fill="y")
        Label(left, text="Scenarios").pack(anchor="w")
        self.scenario_list = Listbox(left, width=38, height=24, exportselection=False)
        self.scenario_list.pack(side=LEFT, fill="y")
        scroller = Scrollbar(left, command=self.scenario_list.yview)
        scroller.pack(side=RIGHT, fill="y")
        self.scenario_list.config(yscrollcommand=scroller.set)
        for scenario in self.scenarios:
            self.scenario_list.insert(END, f"{scenario.order:03d} - {scenario.title}")
        self.scenario_list.selection_set(0)
        self.scenario_list.bind("<<ListboxSelect>>", lambda _event: self.refresh_scenario_text())

        right = Frame(main)
        right.pack(side=LEFT, fill=BOTH, expand=True, padx=(12, 0))
        Label(right, text="Etapes").pack(anchor="w")
        self.steps_text = Text(right, height=18, wrap="word")
        self.steps_text.pack(fill=BOTH, expand=True)

        name_frame = Frame(right)
        name_frame.pack(fill="x", pady=(8, 0))
        Label(name_frame, text="Capture").pack(side=LEFT)
        Entry(name_frame, textvariable=self.capture_name).pack(side=LEFT, fill="x", expand=True, padx=6)
        Button(name_frame, text="Copier nom capture", command=self.copy_capture_name).pack(side=LEFT)

        buttons = Frame(right)
        buttons.pack(fill="x", pady=8)
        Button(buttons, text="Start Scenario", command=self.start_scenario, width=16).pack(side=LEFT)
        Button(buttons, text="Action faite", command=self.mark_action_done, width=14).pack(side=LEFT, padx=6)
        Button(buttons, text="Skip etape", command=self.skip_step, width=12).pack(side=LEFT)
        Button(buttons, text="Stop Scenario", command=self.stop_scenario, width=14).pack(side=LEFT, padx=6)

        Label(self.root, textvariable=self.status, anchor="w").pack(fill="x", padx=10, pady=(0, 8))

    def add_labeled_entry(self, parent: Frame, label: str, var: StringVar, width: int) -> None:
        frame = Frame(parent)
        frame.pack(side=LEFT, padx=(0, 10))
        Label(frame, text=label).pack(anchor="w")
        Entry(frame, textvariable=var, width=width).pack()

    def add_labeled_option(
        self,
        parent: Frame,
        label: str,
        var: StringVar,
        values: list[str],
        command=None,
    ) -> None:
        frame = Frame(parent)
        frame.pack(side=LEFT, padx=(0, 10))
        Label(frame, text=label).pack(anchor="w")
        OptionMenu(frame, var, *values, command=command).pack(fill="x")

    def selected_scenario(self) -> Scenario:
        selection = self.scenario_list.curselection()
        index = selection[0] if selection else 0
        return self.scenarios[index]

    def on_settings_changed(self, _value: str) -> None:
        self.scenarios = self.load_scenarios()
        self.scenario_list.delete(0, END)
        for scenario in self.scenarios:
            self.scenario_list.insert(END, f"{scenario.order:03d} - {scenario.title}")
        self.scenario_list.selection_set(0)
        self.output_dir.set(str(self.default_output_dir()))
        self.refresh_scenario_text()

    def choose_output_dir(self) -> None:
        selected = filedialog.askdirectory(initialdir=self.output_dir.get())
        if selected:
            self.output_dir.set(selected)

    def open_output_dir(self) -> None:
        path = Path(self.output_dir.get())
        path.mkdir(parents=True, exist_ok=True)
        os.startfile(path)  # type: ignore[attr-defined]

    def copy_capture_name(self) -> None:
        self.root.clipboard_clear()
        self.root.clipboard_append(self.capture_name.get())
        self.status.set("Nom de capture copie.")

    def refresh_scenario_text(self) -> None:
        scenario = self.selected_scenario()
        self.steps_text.delete("1.0", END)
        for idx, step in enumerate(scenario.steps, start=1):
            self.steps_text.insert(END, f"{idx}. {step}\n")
        self.update_capture_name_preview(scenario)

    def update_capture_name_preview(self, scenario: Scenario) -> None:
        timestamp = datetime.now().strftime("%H%M%S")
        self.capture_name.set(f"{scenario.file_stem}_{timestamp}.pcapng")

    def start_scenario(self) -> None:
        if self.capture_process is not None:
            messagebox.showwarning("Capture active", "Stoppe le scenario actif avant d'en lancer un autre.")
            return

        scenario = self.selected_scenario()
        self.active_scenario = scenario
        self.active_step_index = 0
        self.event_log = []

        out_dir = Path(self.output_dir.get())
        out_dir.mkdir(parents=True, exist_ok=True)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        pcap_name = f"{scenario.file_stem}_{timestamp}.pcapng"
        json_name = f"{scenario.file_stem}_{timestamp}.json"
        self.active_pcap = out_dir / pcap_name
        self.active_json = out_dir / json_name
        self.capture_name.set(str(self.active_pcap))

        self.log_event("scenario_started", step=None)
        started = self.start_dumpcap()
        if started:
            self.log_event("pcap_started", step=None)
            self.status.set(f"Capture lancee: {self.active_pcap}")
        else:
            self.log_event("pcap_manual_mode", step=None)
            self.status.set(f"Mode manuel: utilise ce nom dans Wireshark: {self.active_pcap}")

        self.write_json()
        self.show_current_step()

    def start_dumpcap(self) -> bool:
        if not DUMPCAP.exists() or self.active_pcap is None:
            return False

        iface = self.interface.get()
        match = re.match(r"^(\d+)\s+-", iface)
        if not match:
            return False

        capture_filter = f"host {self.ip.get().strip()} or tcp port {self.port.get().strip()}"
        cmd = [
            str(DUMPCAP),
            "-i",
            match.group(1),
            "-f",
            capture_filter,
            "-w",
            str(self.active_pcap),
        ]
        try:
            creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
            self.capture_process = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                creationflags=creationflags,
            )
            self.root.after(500, self.poll_capture_process)
            return True
        except Exception as exc:
            self.log_event("pcap_start_failed", step=None, extra={"error": str(exc), "command": cmd})
            self.capture_process = None
            return False

    def poll_capture_process(self) -> None:
        proc = self.capture_process
        if proc is None:
            return
        code = proc.poll()
        if code is None:
            self.root.after(1000, self.poll_capture_process)
            return
        stderr = ""
        try:
            stderr = proc.stderr.read() if proc.stderr else ""
        except Exception:
            pass
        self.log_event("pcap_process_exited", step=None, extra={"returncode": code, "stderr": stderr[-2000:]})
        self.capture_process = None
        self.write_json()
        self.status.set(f"dumpcap termine avec code {code}. Le guidage reste actif.")

    def show_current_step(self) -> None:
        scenario = self.active_scenario
        if scenario is None:
            return
        self.steps_text.delete("1.0", END)
        for idx, step in enumerate(scenario.steps):
            prefix = ">> " if idx == self.active_step_index else "   "
            done = "[x] " if idx < self.active_step_index else "[ ] "
            self.steps_text.insert(END, f"{prefix}{done}{idx + 1}. {step}\n")
        if self.active_step_index < len(scenario.steps):
            self.log_event("step_prompted", step=self.active_step_index + 1)
            self.write_json()

    def mark_action_done(self) -> None:
        scenario = self.active_scenario
        if scenario is None:
            messagebox.showinfo("Aucun scenario", "Lance d'abord un scenario.")
            return
        if self.active_step_index >= len(scenario.steps):
            self.status.set("Toutes les etapes sont deja terminees. Tu peux stopper le scenario.")
            return
        self.log_event("step_done", step=self.active_step_index + 1)
        self.active_step_index += 1
        self.write_json()
        if self.active_step_index >= len(scenario.steps):
            self.status.set("Scenario termine cote actions. Clique Stop Scenario pour fermer la capture.")
        self.show_current_step()

    def skip_step(self) -> None:
        scenario = self.active_scenario
        if scenario is None:
            messagebox.showinfo("Aucun scenario", "Lance d'abord un scenario.")
            return
        if self.active_step_index < len(scenario.steps):
            self.log_event("step_skipped", step=self.active_step_index + 1)
            self.active_step_index += 1
            self.write_json()
            self.show_current_step()

    def stop_scenario(self) -> None:
        if self.active_scenario is None and self.capture_process is None:
            self.status.set("Aucun scenario actif.")
            return

        self.stop_dumpcap()
        self.log_event("scenario_stopped", step=None)
        self.write_json()
        self.status.set(f"Scenario stoppe. Journal: {self.active_json}")
        self.active_scenario = None
        self.active_step_index = 0
        self.refresh_scenario_text()

    def stop_dumpcap(self) -> None:
        proc = self.capture_process
        if proc is None:
            return
        self.log_event("pcap_stopping", step=None)
        try:
            proc.terminate()
            proc.wait(timeout=5)
        except Exception:
            try:
                proc.kill()
                proc.wait(timeout=2)
            except Exception:
                pass
        finally:
            self.capture_process = None
            self.log_event("pcap_stopped", step=None)

    def log_event(self, event: str, step: int | None, extra: dict | None = None) -> None:
        scenario = self.active_scenario
        payload = {
            "event": event,
            "at": datetime.now().isoformat(timespec="milliseconds"),
            "scenario": scenario.key if scenario else None,
            "step": step,
        }
        if extra:
            payload.update(extra)
        self.event_log.append(payload)

    def write_json(self) -> None:
        if self.active_json is None:
            return
        scenario = self.active_scenario
        data = {
            "tool": "dsp_capture_helper",
            "created_at": datetime.now().isoformat(timespec="milliseconds"),
            "device_model": self.model.get(),
            "dsp_ip": self.ip.get().strip(),
            "port": int(self.port.get().strip()) if self.port.get().strip().isdigit() else self.port.get().strip(),
            "interface": self.interface.get(),
            "dumpcap": str(DUMPCAP),
            "capture_file": str(self.active_pcap) if self.active_pcap else None,
            "scenario": {
                "key": scenario.key if scenario else None,
                "title": scenario.title if scenario else None,
                "steps": list(scenario.steps) if scenario else [],
            },
            "completed_steps": self.active_step_index,
            "events": self.event_log,
        }
        self.active_json.parent.mkdir(parents=True, exist_ok=True)
        self.active_json.write_text(json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8")

    def on_close(self) -> None:
        if self.capture_process is not None:
            if not messagebox.askyesno("Capture active", "Une capture est active. Stopper et quitter ?"):
                return
            self.stop_scenario()
        self.root.destroy()


def main() -> None:
    root = Tk()
    app = CaptureHelperApp(root)
    root.mainloop()


if __name__ == "__main__":
    main()
