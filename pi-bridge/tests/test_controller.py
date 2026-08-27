import unittest

from app.controller import ControllerBusy, ParkingController


class ParkingControllerTest(unittest.IsolatedAsyncioTestCase):
    async def test_parking_and_retrieval_flow(self) -> None:
        controller = ParkingController(step_delay_seconds=0.001)

        response = await controller.request_parking("snap-01", 120, "AUTO")
        self.assertTrue(response["requestId"].startswith("REQ-"))
        self.assertEqual(response["snapshot"]["job"]["targetSlot"], "B2")

        await controller.wait_until("PARKED", timeout=1)
        parked = controller.snapshot()
        target = next(slot for slot in parked["slots"] if slot["id"] == "B2")
        self.assertEqual(target["state"], "OCCUPIED")
        self.assertEqual(target["vehicleId"], "SNAP-01")

        await controller.request_retrieval("SNAP-01")
        await controller.wait_until("IDLE", timeout=1)
        retrieved = controller.snapshot()
        target = next(slot for slot in retrieved["slots"] if slot["id"] == "B2")
        self.assertEqual(target["state"], "AVAILABLE")
        self.assertNotIn("vehicleId", target)

    async def test_rejects_conflicting_request(self) -> None:
        controller = ParkingController(step_delay_seconds=0.05)
        await controller.request_parking("SNAP-01", 120, "AUTO")

        with self.assertRaises(ControllerBusy):
            await controller.request_parking("SNAP-02", 30, "NEAR_EXIT")


if __name__ == "__main__":
    unittest.main()
