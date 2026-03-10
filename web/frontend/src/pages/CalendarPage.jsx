import { useCallback, useEffect, useMemo, useState } from "react";
import { useAuth } from "../context/AuthContext";
import {
  clearStoredCalendarAccessToken,
  connectGoogleCalendar,
  fetchGoogleCalendarEvents,
  getStoredCalendarAccessToken,
} from "../api/calendarApi";
import LoadingSpinner from "../components/shared/LoadingSpinner";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../components/ui/card";

const HOURS = Array.from({ length: 24 }, (_, hour) => hour);
const HOUR_HEIGHT = 58;
const TIME_RAIL_WIDTH = 84;

function startOfDay(date) {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate());
}

function addDays(date, amount) {
  const result = new Date(date);
  result.setDate(result.getDate() + amount);
  return result;
}

function startOfWeek(date) {
  const result = startOfDay(date);
  const day = result.getDay();
  const diff = day === 0 ? -6 : 1 - day;
  return addDays(result, diff);
}

function sameDay(left, right) {
  return left.getFullYear() === right.getFullYear()
    && left.getMonth() === right.getMonth()
    && left.getDate() === right.getDate();
}

function parseEventDate(value) {
  if (!value) return null;
  if (value.dateTime) return new Date(value.dateTime);
  if (value.date) return new Date(`${value.date}T00:00:00`);
  return null;
}

function getEventStart(event) {
  return parseEventDate(event.start);
}

function getEventEnd(event) {
  const start = getEventStart(event);
  const end = parseEventDate(event.end);
  if (end) return end;
  if (start) return new Date(start.getTime() + 60 * 60 * 1000);
  return null;
}

function isAllDayEvent(event) {
  return Boolean(event.start?.date && !event.start?.dateTime);
}

function formatHour(hour) {
  const period = hour >= 12 ? "PM" : "AM";
  const value = hour % 12 || 12;
  return `${value}:00 ${period}`;
}

function formatMonthLabel(date) {
  return date.toLocaleDateString(undefined, { month: "long", year: "numeric" });
}

function formatDayLabel(date) {
  return date.toLocaleDateString(undefined, { weekday: "short" });
}

function formatEventTime(event) {
  const start = getEventStart(event);
  const end = getEventEnd(event);
  if (!start) return "Time unavailable";
  if (isAllDayEvent(event)) return "All day";
  return `${start.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })} - ${end?.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" }) || ""}`;
}

function getEventDayKey(event) {
  const start = getEventStart(event);
  return start ? startOfDay(start).toISOString() : null;
}

function buildVisibleRange(anchorMonth) {
  const weekStart = startOfWeek(new Date(anchorMonth.getFullYear(), anchorMonth.getMonth(), 1));
  return {
    start: addDays(weekStart, -14),
    end: addDays(weekStart, 63),
  };
}

function filterEventsForDate(events, date) {
  const dayStart = startOfDay(date);
  const nextDay = addDays(dayStart, 1);

  return events.filter((event) => {
    const start = getEventStart(event);
    const end = getEventEnd(event) || start;
    if (!start) return false;
    return start < nextDay && end > dayStart;
  });
}

function buildEventLayouts(events, date) {
  const dayStart = startOfDay(date);
  const pixelsPerMinute = HOUR_HEIGHT / 60;
  const timedEvents = events
    .filter((event) => !isAllDayEvent(event))
    .map((event) => ({ event, start: getEventStart(event), end: getEventEnd(event) }))
    .filter((entry) => entry.start && entry.end)
    .sort((left, right) => left.start - right.start);

  if (timedEvents.length === 0) return [];

  const groups = [];
  let currentGroup = [];
  let currentGroupEnd = null;

  for (const entry of timedEvents) {
    if (!currentGroup.length) {
      currentGroup = [entry];
      currentGroupEnd = entry.end;
      continue;
    }

    if (entry.start < currentGroupEnd) {
      currentGroup.push(entry);
      if (entry.end > currentGroupEnd) currentGroupEnd = entry.end;
    } else {
      groups.push(currentGroup);
      currentGroup = [entry];
      currentGroupEnd = entry.end;
    }
  }

  if (currentGroup.length) groups.push(currentGroup);

  return groups.flatMap((group) => {
    const columns = [];
    const placements = [];

    for (const entry of group) {
      let columnIndex = columns.findIndex((columnEnd) => columnEnd <= entry.start);
      if (columnIndex === -1) {
        columns.push(entry.end);
        columnIndex = columns.length - 1;
      } else {
        columns[columnIndex] = entry.end;
      }
      placements.push({ ...entry, columnIndex });
    }

    return placements.map((placement) => {
      const startMinutes = Math.max(0, (placement.start - dayStart) / 60000);
      const endMinutes = Math.min(24 * 60, (placement.end - dayStart) / 60000);
      const durationMinutes = Math.max(30, endMinutes - startMinutes);
      const widthPercent = 100 / columns.length;

      return {
        event: placement.event,
        top: startMinutes * pixelsPerMinute,
        height: durationMinutes * pixelsPerMinute,
        left: `calc(${TIME_RAIL_WIDTH}px + ${placement.columnIndex * widthPercent}% + 6px)`,
        width: `calc(${widthPercent}% - 12px)`,
      };
    });
  });
}

export default function CalendarPage() {
  const { user } = useAuth();
  const displayName = user?.displayName || user?.email?.split("@")[0] || "there";

  const [accessToken, setAccessToken] = useState(null);
  const [events, setEvents] = useState([]);
  const [isLoading, setIsLoading] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [error, setError] = useState("");
  const [selectedDate, setSelectedDate] = useState(startOfDay(new Date()));
  const [currentMonth, setCurrentMonth] = useState(startOfDay(new Date()));
  const [selectedEvent, setSelectedEvent] = useState(null);

  useEffect(() => {
    if (!user?.uid) {
      setAccessToken(null);
      setEvents([]);
      return;
    }

    setAccessToken(getStoredCalendarAccessToken(user.uid));
  }, [user?.uid]);

  const visibleRange = useMemo(() => buildVisibleRange(currentMonth), [currentMonth]);
  const rangeStartMs = visibleRange.start.getTime();
  const rangeEndMs = visibleRange.end.getTime();

  const loadEvents = useCallback(async (token) => {
    if (!token) return;

    setIsLoading(true);
    setError("");

    try {
      const fetched = await fetchGoogleCalendarEvents({
        accessToken: token,
        start: new Date(rangeStartMs),
        end: new Date(rangeEndMs),
      });
      setEvents(fetched);
    } catch (fetchError) {
      if (fetchError.status === 401 || fetchError.status === 403) {
        clearStoredCalendarAccessToken(user?.uid);
        setAccessToken(null);
        setError("Google Calendar access expired. Reconnect to continue.");
      } else {
        setError(fetchError.message || "Unable to load Google Calendar.");
      }
    } finally {
      setIsLoading(false);
    }
  }, [rangeEndMs, rangeStartMs, user?.uid]);

  useEffect(() => {
    if (accessToken) {
      loadEvents(accessToken);
    }
  }, [accessToken, loadEvents]);

  useEffect(() => {
    if (!sameDay(selectedDate, currentMonth) && selectedDate.getMonth() !== currentMonth.getMonth()) {
      setCurrentMonth(startOfDay(selectedDate));
    }
  }, [selectedDate, currentMonth]);

  const dayEvents = useMemo(() => filterEventsForDate(events, selectedDate), [events, selectedDate]);
  const allDayEvents = dayEvents.filter((event) => isAllDayEvent(event));
  const timedLayouts = useMemo(() => buildEventLayouts(dayEvents, selectedDate), [dayEvents, selectedDate]);

  const eventDays = useMemo(() => {
    const set = new Set();
    for (const event of events) {
      const key = getEventDayKey(event);
      if (key) set.add(key);
    }
    return set;
  }, [events]);

  const weekStart = useMemo(() => startOfWeek(selectedDate), [selectedDate]);
  const weekDays = useMemo(() => Array.from({ length: 7 }, (_, index) => addDays(weekStart, index)), [weekStart]);

  const currentTimeOffset = useMemo(() => {
    if (!sameDay(selectedDate, new Date())) return null;
    const now = new Date();
    const minutes = ((now - startOfDay(now)) / 60000);
    return minutes * (HOUR_HEIGHT / 60);
  }, [selectedDate]);

  const handleConnect = async () => {
    setIsConnecting(true);
    setError("");

    try {
      const token = await connectGoogleCalendar();
      setAccessToken(token);
    } catch (connectError) {
      setError(connectError.message || "Unable to connect Google Calendar.");
    } finally {
      setIsConnecting(false);
    }
  };

  const handleMonthChange = (event) => {
    const [year, month] = event.target.value.split("-").map(Number);
    if (!year || !month) return;
    const nextDate = new Date(year, month - 1, 1);
    setCurrentMonth(nextDate);
    setSelectedDate(nextDate);
  };

  const shiftWeek = (direction) => {
    const nextDate = addDays(selectedDate, direction * 7);
    setSelectedDate(nextDate);
    setCurrentMonth(nextDate);
  };

  return (
    <div className="page-container fade-in">
      <div className="stack">
        <Card variant="hero">
          <CardContent>
            <div className="hero-layout">
              <div className="stack">
                <h1 className="page-title">Calendar</h1>
                <div className="toolbar-actions">
                  <button className="btn btn-secondary" onClick={handleConnect} disabled={isConnecting}>
                    {isConnecting ? "Connecting..." : accessToken ? "Reconnect Google Calendar" : "Connect Google Calendar"}
                  </button>
                  {accessToken && (
                    <button className="btn btn-ghost" onClick={() => loadEvents(accessToken)} disabled={isLoading}>
                      Refresh Events
                    </button>
                  )}
                </div>
              </div>

              <div className="hero-metrics">
                <div className="metric-card">
                  <div className="metric-label">Connection</div>
                  <div className="metric-value" style={{ fontSize: "1.3rem" }}>
                    {accessToken ? "Live" : "Offline"}
                  </div>
                  <div className="metric-meta">{accessToken ? "connected" : "not connected"}</div>
                </div>
                <div className="metric-card">
                  <div className="metric-label">{displayName}</div>
                  <div className="metric-value" style={{ fontSize: "1.3rem" }}>
                    {dayEvents.length}
                  </div>
                  <div className="metric-meta">events on {selectedDate.toLocaleDateString(undefined, { month: "short", day: "numeric" })}</div>
                </div>
              </div>
            </div>
          </CardContent>
        </Card>

        <div className="dashboard-grid dashboard-grid--two">
          <Card>
            <CardHeader>
              <div>
                <CardTitle>Google Calendar</CardTitle>
              </div>
              <span className={`status-pill${accessToken ? "" : " status-pill--danger"}`}>
                {accessToken ? "Connected" : "Needs Google auth"}
              </span>
            </CardHeader>
            <CardContent>
              {error && <div className="error-banner" style={{ marginBottom: "1rem" }}>{error}</div>}

              <div className="calendar-toolbar">
                <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap", alignItems: "center" }}>
                  <button className="btn btn-ghost btn-sm" onClick={() => shiftWeek(-1)}>
                    Previous Week
                  </button>
                  <button className="btn btn-ghost btn-sm" onClick={() => shiftWeek(1)}>
                    Next Week
                  </button>
                  <button className="btn btn-secondary btn-sm" onClick={() => setSelectedDate(startOfDay(new Date()))}>
                    Today
                  </button>
                </div>

                <div style={{ display: "flex", gap: "0.75rem", alignItems: "center", flexWrap: "wrap" }}>
                  <div className="calendar-month-label">{formatMonthLabel(currentMonth)}</div>
                  <input
                    type="month"
                    value={`${currentMonth.getFullYear()}-${String(currentMonth.getMonth() + 1).padStart(2, "0")}`}
                    onChange={handleMonthChange}
                    style={{ width: 180 }}
                  />
                </div>
              </div>

              <div className="calendar-week-strip">
                {weekDays.map((date) => {
                  const isSelected = sameDay(date, selectedDate);
                  const hasEvents = eventDays.has(startOfDay(date).toISOString());
                  const isToday = sameDay(date, new Date());

                  return (
                    <button
                      key={date.toISOString()}
                      type="button"
                      className={`calendar-day-button${isSelected ? " calendar-day-button--selected" : ""}${isToday ? " calendar-day-button--today" : ""}`}
                      onClick={() => setSelectedDate(startOfDay(date))}
                    >
                      <span className="calendar-day-button__label">{formatDayLabel(date)}</span>
                      <span className="calendar-day-button__date">{date.getDate()}</span>
                      <span className={`calendar-day-button__dot${hasEvents ? " calendar-day-button__dot--active" : ""}`} />
                    </button>
                  );
                })}
              </div>

              {isLoading ? (
                <div className="loading-center">
                  <LoadingSpinner size={42} />
                </div>
              ) : !accessToken ? (
                <div className="empty-state">Connect Google Calendar to render the same scheduling view the iOS app uses.</div>
              ) : (
                <div className="calendar-timeline-shell">
                  {allDayEvents.length > 0 && (
                    <div className="calendar-all-day-row">
                      <div className="calendar-all-day-row__label">All day</div>
                      <div className="calendar-all-day-row__events">
                        {allDayEvents.map((event) => (
                          <button
                            key={event.id}
                            type="button"
                            className="calendar-pill-event"
                            onClick={() => setSelectedEvent(event)}
                          >
                            {event.summary || "Untitled event"}
                          </button>
                        ))}
                      </div>
                    </div>
                  )}

                  <div className="calendar-timeline-grid" style={{ height: HOURS.length * HOUR_HEIGHT }}>
                    {HOURS.map((hour) => (
                      <div key={hour} className="calendar-hour-row" style={{ height: HOUR_HEIGHT }}>
                        <div className="calendar-hour-row__label">{formatHour(hour)}</div>
                        <div className="calendar-hour-row__line" />
                      </div>
                    ))}

                    {currentTimeOffset !== null && (
                      <div className="calendar-now-indicator" style={{ top: currentTimeOffset }}>
                        <span className="calendar-now-indicator__dot" />
                        <span className="calendar-now-indicator__line" />
                      </div>
                    )}

                    {timedLayouts.map((layout) => (
                      <button
                        key={layout.event.id}
                        type="button"
                        className="calendar-event-block"
                        style={{ top: layout.top, height: layout.height, left: layout.left, width: layout.width }}
                        onClick={() => setSelectedEvent(layout.event)}
                      >
                        <span className="calendar-event-block__title">{layout.event.summary || "Untitled event"}</span>
                        <span className="calendar-event-block__time">{formatEventTime(layout.event)}</span>
                        {layout.event.location && <span className="calendar-event-block__meta">{layout.event.location}</span>}
                      </button>
                    ))}

                    {!allDayEvents.length && !timedLayouts.length && (
                      <div className="calendar-empty-day">
                        No Google Calendar events on this day.
                      </div>
                    )}
                  </div>
                </div>
              )}
            </CardContent>
          </Card>

          <div className="stack">
            <Card variant="accent">
              <CardHeader>
                <div>
                  <CardTitle>{selectedDate.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}</CardTitle>
                </div>
              </CardHeader>
              <CardContent>
                <div className="list">
                  {dayEvents.length === 0 ? (
                    <div className="empty-state">The day is currently clear.</div>
                  ) : (
                    dayEvents.map((event) => (
                      <button
                        key={event.id}
                        type="button"
                        className="list-item"
                        style={{ textAlign: "left", width: "100%", border: "1px solid rgba(69, 90, 44, 0.08)" }}
                        onClick={() => setSelectedEvent(event)}
                      >
                        <div className="list-item__copy">
                          <span className="list-item__title">{event.summary || "Untitled event"}</span>
                          <span className="list-item__meta">{formatEventTime(event)}</span>
                        </div>
                        <span className="status-pill">Event</span>
                      </button>
                    ))
                  )}
                </div>
              </CardContent>
            </Card>
          </div>
        </div>
      </div>

      {selectedEvent && (
        <div className="modal-overlay" onClick={(event) => event.target === event.currentTarget && setSelectedEvent(null)}>
          <div className="modal-panel">
            <div className="stack">
              <div className="stack--sm">
                <h2 className="page-title" style={{ fontSize: "1.8rem" }}>{selectedEvent.summary || "Untitled event"}</h2>
                <p className="page-summary">{formatEventTime(selectedEvent)}</p>
              </div>

              <div className="list">
                {selectedEvent.location && (
                  <div className="list-item">
                    <div className="list-item__copy">
                      <span className="list-item__title">Location</span>
                      <span className="list-item__meta">{selectedEvent.location}</span>
                    </div>
                  </div>
                )}
                {selectedEvent.description && (
                  <div className="list-item">
                    <div className="list-item__copy">
                      <span className="list-item__title">Description</span>
                      <span className="list-item__meta" style={{ whiteSpace: "pre-wrap" }}>{selectedEvent.description}</span>
                    </div>
                  </div>
                )}
              </div>

              <div style={{ display: "flex", gap: "0.75rem", flexWrap: "wrap" }}>
                {selectedEvent.htmlLink && (
                  <a className="btn btn-primary" href={selectedEvent.htmlLink} target="_blank" rel="noreferrer">
                    Open in Google Calendar
                  </a>
                )}
                <button className="btn btn-secondary" onClick={() => setSelectedEvent(null)}>
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}



