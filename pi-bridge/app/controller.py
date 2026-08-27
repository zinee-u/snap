from __future__ import annotations

import asyncio
from copy import deepcopy
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4


class ControllerError(RuntimeError):
    """Base error exposed by the Pi controller boundary."""


class ControllerBusy(ControllerError):
    """Raised when a conflicting robot job is already running."""


class VehicleNotFound(ControllerError):
    """Raised when a retrieval request cannot find the requested vehicle."""


class ParkingController:
    """In-memory Pi demo controller with the same boundary as future hardware code.

    The web/API contract is production-shaped, while the transitions are deliberately
    simulated until the Arduino/serial command set is confirmed with the Pi owner.
    """

    slot_ids = ("A1", "A2", "A3", "B1", "B2", "B3")
    target_by_preference = {
        "AUTO": "B2",
        "NEAR_EXIT": "A1",
        "SHORTEST_PATH": "B1",
    }
    reason_by_preference = {
        "AUTO": ("AUTO_BALANCED", "입구와 출구 동선을 균형 있게 고려했어요."),
        "NEAR_EXIT": ("NEAR_EXIT", "예상 출차 시각에 맞춰 출구 가까운 면을 골랐어요."),
        "SHORTEST_PATH": ("SHORTEST_PATH", "현재 로봇 위치에서 이동 거리가 가장 짧아요."),
    }

    def __init__(self, step_delay_seconds: float = 1.05) -> None:
        self.step_delay_seconds = max(0.0, step_delay_seconds)
        self._lock = asyncio.Lock()
        self._subscribers: set[asyncio.Queue[dict[str, Any]]] = set()
        self._active_task: asyncio.Task[None] | None = None
        self._slots = [
            {
                "id": slot_id,
                "state": "OCCUPIED" if slot_id == "A2" else "RESERVED" if slot_id == "B2" else "AVAILABLE",
                **({"vehicleId": "SNAP-88"} if slot_id == "A2" else {}),
            }
            for slot_id in self.slot_ids
        ]
        self._robot = {
            "state": "입구에서 대기 중",
            "batteryPct": 86,
            "positionPct": 18,
        }
        self._job = {
            "state": "IDLE",
            "targetSlot": "B2",
            "reasonCode": "AUTO_BALANCED",
            "reason": "입구와 출구 동선을 균형 있게 고려했어요.",
            "message": "주차 요청을 기다리고 있어요.",
        }
        self._updated_at = self._now()

    @staticmethod
    def _now() -> str:
        return datetime.now(timezone.utc).isoformat()

    def snapshot(self) -> dict[str, Any]:
        return {
            "lotId": "demo-01",
            "updatedAt": self._updated_at,
            "slots": deepcopy(self._slots),
            "robot": deepcopy(self._robot),
            "job": deepcopy(self._job),
        }

    def subscribe(self) -> asyncio.Queue[dict[str, Any]]:
        queue: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=16)
        self._subscribers.add(queue)
        return queue

    def unsubscribe(self, queue: asyncio.Queue[dict[str, Any]]) -> None:
        self._subscribers.discard(queue)

    async def request_parking(
        self,
        vehicle_id: str,
        expected_minutes: int,
        preference: str,
    ) -> dict[str, Any]:
        del expected_minutes  # Kept in the public contract for the future allocator.
        normalized_vehicle = vehicle_id.strip().upper()
        normalized_preference = preference.strip().upper()

        async with self._lock:
            if self._job["state"] != "IDLE":
                raise ControllerBusy("다른 주차·출차 작업이 진행 중입니다.")

            target = self._select_target(normalized_preference)
            reason_code, reason = self.reason_by_preference.get(
                normalized_preference,
                self.reason_by_preference["AUTO"],
            )
            request_id = f"REQ-{uuid4().hex[:8].upper()}"
            self._reserve_target(target)
            self._job = {
                "id": request_id,
                "state": "REQUESTED",
                "vehicleId": normalized_vehicle,
                "targetSlot": target,
                "reasonCode": reason_code,
                "reason": reason,
                "message": "주차 요청을 안전 제어기에 전달했어요.",
            }
            self._robot["state"] = self._job["message"]
            self._updated_at = self._now()
            self._active_task = asyncio.create_task(
                self._run_parking(request_id, normalized_vehicle, target),
            )

        await self._broadcast("JOB_REQUESTED", self._job["message"])
        return {"requestId": request_id, "snapshot": self.snapshot()}

    async def confirm_parking(self, request_id: str) -> dict[str, Any]:
        if self._job.get("id") != request_id:
            raise ControllerError("해당 주차 요청을 찾을 수 없습니다.")
        return {"requestId": request_id, "confirmed": True, "snapshot": self.snapshot()}

    async def request_retrieval(self, vehicle_id: str) -> dict[str, Any]:
        normalized_vehicle = vehicle_id.strip().upper()
        async with self._lock:
            if self._job["state"] != "PARKED":
                raise ControllerBusy("출차할 수 있는 완료 차량이 없습니다.")

            parked_slot = next(
                (slot for slot in self._slots if slot.get("vehicleId") == normalized_vehicle),
                None,
            )
            if parked_slot is None:
                raise VehicleNotFound(f"차량 {normalized_vehicle}을(를) 찾을 수 없습니다.")

            request_id = f"RET-{uuid4().hex[:8].upper()}"
            self._job = {
                **self._job,
                "id": request_id,
                "state": "RETRIEVING",
                "vehicleId": normalized_vehicle,
                "targetSlot": parked_slot["id"],
                "message": f"{parked_slot['id']} 주차면으로 이동 중이에요.",
            }
            self._robot.update({"state": self._job["message"], "positionPct": 72})
            self._updated_at = self._now()
            self._active_task = asyncio.create_task(
                self._run_retrieval(request_id, normalized_vehicle, parked_slot["id"]),
            )

        await self._broadcast("RETRIEVAL_REQUESTED", self._job["message"])
        return {"requestId": request_id, "snapshot": self.snapshot()}

    def get_job(self, job_id: str) -> dict[str, Any]:
        if self._job.get("id") != job_id:
            raise ControllerError("해당 작업을 찾을 수 없습니다.")
        return deepcopy(self._job)

    async def wait_until(self, state: str, timeout: float = 5.0) -> None:
        async def wait() -> None:
            while self._job["state"] != state:
                await asyncio.sleep(0.005)

        await asyncio.wait_for(wait(), timeout=timeout)

    def _select_target(self, preference: str) -> str:
        preferred = self.target_by_preference.get(preference, self.target_by_preference["AUTO"])
        candidates = [
            slot["id"]
            for slot in self._slots
            if slot["state"] in {"AVAILABLE", "RESERVED"}
        ]
        if not candidates:
            raise ControllerBusy("현재 사용할 수 있는 주차면이 없습니다.")
        return preferred if preferred in candidates else candidates[0]

    def _reserve_target(self, target: str) -> None:
        for slot in self._slots:
            if slot["state"] == "RESERVED":
                slot["state"] = "AVAILABLE"
            if slot["id"] == target:
                slot["state"] = "RESERVED"
                slot.pop("vehicleId", None)

    async def _run_parking(self, request_id: str, vehicle_id: str, target: str) -> None:
        steps = (
            ("VEHICLE_DETECTED", "입구 센서가 차량을 확인했어요.", 24),
            ("MOVING_TO_VEHICLE", "로봇이 차량 아래로 이동 중이에요.", 37),
            ("LIFTING", "차량을 들어 올리고 안전 상태를 확인해요.", 49),
            ("MOVING_TO_SLOT", "추천 주차면으로 차량을 옮기고 있어요.", 73),
            ("PARKED", "주차가 완료됐어요. 출차 요청을 기다릴게요.", 82),
        )
        for state, message, position in steps:
            await asyncio.sleep(self.step_delay_seconds)
            async with self._lock:
                if self._job.get("id") != request_id:
                    return
                self._job.update({"state": state, "message": message})
                self._robot.update({
                    "state": message,
                    "positionPct": position,
                    "batteryPct": max(0, self._robot["batteryPct"] - 1),
                })
                if state == "PARKED":
                    for slot in self._slots:
                        if slot["id"] == target:
                            slot.update({"state": "OCCUPIED", "vehicleId": vehicle_id})
                self._updated_at = self._now()
            await self._broadcast(state, message)

    async def _run_retrieval(self, request_id: str, vehicle_id: str, target: str) -> None:
        steps = (
            ("RETURNING", "차량을 입구 인계 구역으로 옮기고 있어요.", 36),
            ("IDLE", "출차가 완료됐어요. 다음 요청을 기다릴게요.", 18),
        )
        for state, message, position in steps:
            await asyncio.sleep(self.step_delay_seconds * 1.2)
            async with self._lock:
                if self._job.get("id") != request_id:
                    return
                self._job.update({"state": state, "message": message})
                self._robot.update({"state": message, "positionPct": position})
                if state == "IDLE":
                    for slot in self._slots:
                        if slot["id"] == target and slot.get("vehicleId") == vehicle_id:
                            slot["state"] = "AVAILABLE"
                            slot.pop("vehicleId", None)
                    self._job.pop("vehicleId", None)
                self._updated_at = self._now()
            await self._broadcast(state, message)

    async def _broadcast(self, event_type: str, message: str) -> None:
        event = {
            "type": event_type,
            "message": message,
            "snapshot": self.snapshot(),
        }
        for queue in tuple(self._subscribers):
            if queue.full():
                try:
                    queue.get_nowait()
                except asyncio.QueueEmpty:
                    pass
            queue.put_nowait(deepcopy(event))
