/**
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 */

#pragma once

#include <memory>
#include <mutex>
#include <vector>

#include <ABI35_0_0jsi/ABI35_0_0jsi.h>
#include <ReactABI35_0_0/events/EventBeat.h>
#include <ReactABI35_0_0/events/RawEvent.h>
#include <ReactABI35_0_0/events/primitives.h>

namespace facebook {
namespace ReactABI35_0_0 {

/*
 * Event Queue synchronized with given Event Beat and dispatching event
 * using given Event Pipe.
 */
class EventQueue {
 public:
  EventQueue(EventPipe eventPipe, std::unique_ptr<EventBeat> eventBeat);
  virtual ~EventQueue() = default;

  /*
   * Enqueues and (probably later) dispatch a given event.
   * Can be called on any thread.
   */
  virtual void enqueueEvent(const RawEvent &rawEvent) const;

 protected:
  void onBeat(jsi::Runtime &runtime) const;

  const EventPipe eventPipe_;
  const std::unique_ptr<EventBeat> eventBeat_;
  // Thread-safe, protected by `queueMutex_`.
  mutable std::vector<RawEvent> queue_;
  mutable std::mutex queueMutex_;
};

} // namespace ReactABI35_0_0
} // namespace facebook
