import 'package:polymer/polymer.dart';
import 'dart:html';
import 'package:quiver/iterables.dart';


class ZoomLevel {
  final String cssclass;
  /// height of one hour. must also be configured in css.
  final int heightHour;
  /// the smallest editable/showable time duration in minutes. (15 means only quarter hours can be selected)
  final int minuteFactor;
  /// smallest editable unit * _hourMultiplier = 60
  int hourMultiplier;
  /// height of the smallest editable unites.
  int timeFrameHeight;

  ZoomLevel(this.cssclass, this.heightHour, this.minuteFactor) {
    this.hourMultiplier = 60 ~/ this.minuteFactor;
    timeFrameHeight = heightHour ~/ hourMultiplier;
  }
    
  static final OVERVIEWDAY = new ZoomLevel('zoom-overviewday', 36, 15);
  static final DAY = new ZoomLevel('zoom-day', 60, 15);
  static final QUARTER_HOUR = new ZoomLevel('zoom-quarter-hour', 60*4, 5);
  static final FIVE_MINUTES = new ZoomLevel('zoom-five-minutes', 60 * 16, 1);
  static final MINUTE = new ZoomLevel('zoom-minute', 60 * 64, 1);
  
  static final List<ZoomLevel> values = [OVERVIEWDAY, DAY, QUARTER_HOUR, FIVE_MINUTES, MINUTE];
}

class CalendarEvent {
  int id;
  DateTime start;
  DateTime end;
  String title;
  String description;
  
  CalendarEvent(this.id, this.start, this.end, this.title, this.description);
}


class CalendarInteractionTracker {
  DivElement _eventListWrapperDiv;
  CalendarView _calendarView;
  
  /// div which is currently resizing. (is null if the user is not resizing an element right now.)
  DivElement _resizingEventDiv;
  DivElement _movingEventDiv;
  ZoomLevel _zoomLevel;
  int cursorPosOffsetY = -20;

  CalendarInteractionTracker(this._calendarView, DivElement calendarview, this._eventListWrapperDiv) {
    _zoomLevel = _calendarView._zoomLevel;
    _eventListWrapperDiv
      ..onMouseMove.listen((MouseEvent e) {
        var eventdiv = _movingEventDiv != null ? _movingEventDiv : _resizingEventDiv;
        if (eventdiv == null) {
            return;
        }
//        print('moving event.');
        var y = e.pageY - calendarview.offset.top + calendarview.scrollTop - window.scrollY + cursorPosOffsetY;
        var quarters = (y / _zoomLevel.timeFrameHeight).floor();
        var minutes = (quarters % _zoomLevel.hourMultiplier) * _zoomLevel.minuteFactor;
        var hours = (quarters ~/ _zoomLevel.hourMultiplier).floor();
        
        CalendarEvent event = _calendarView.getEventById(int.parse(eventdiv.attributes['eventid']));

        if (_resizingEventDiv != null) {
          // user is resizing event.
          event.end = new DateTime(event.end.year, event.end.month, event.end.day, hours, minutes);
          Duration diff = event.end.difference(event.start);
          if (diff.inSeconds < _zoomLevel.minuteFactor * 60) {
            event.end = event.start.add(new Duration(minutes: _zoomLevel.minuteFactor));
          }
          // check if we are overlapping with any other event.
          for (CalendarEvent cmpEvent in _calendarView._events) {
            if (cmpEvent.start.compareTo(event.start) > 0 && cmpEvent.start.compareTo(event.end) < 0) {
              event.end = cmpEvent.start;
            }
          }
        } else if (_movingEventDiv != null) {
          // user is moving a event. updating times.
          var before = event.start;
          var diff = event.end.difference(event.start);
          
          event.start = new DateTime(before.year, before.month, before.day, hours, minutes);
          event.end = event.start.add(diff);
          
          // we must not obstruct any other event...
          var compareEvent = checkObstruction(event);
          if(compareEvent != null) {
            print('event is obstracting another event.');
            if (compareEvent.start.compareTo(before) > 0) {
              event.start = compareEvent.start.subtract(diff);
              event.end = new DateTime.fromMillisecondsSinceEpoch(compareEvent.start.millisecondsSinceEpoch, isUtc: compareEvent.start.isUtc);
            } else {
              event.start = new DateTime.fromMillisecondsSinceEpoch(compareEvent.end.millisecondsSinceEpoch, isUtc: compareEvent.end.isUtc);
              event.end = event.start.add(diff);
            }
            // make sure if the event is now obstructing any other event.
            if (checkObstruction(event) != null) {
              // ok, give up.
              event.start = before;
              event.end = event.start.add(diff);
            }
          }
        }
        
        _calendarView._updateEvent(event, eventdiv);
      })
      ..onMouseUp.listen((MouseEvent e) {
        if (_movingEventDiv != null) {
          _movingEventDiv.classes.remove('moving');
          _movingEventDiv = null;
        }
        if (_resizingEventDiv != null) {
          _resizingEventDiv.classes.remove('resizing');
          _resizingEventDiv = null;
        }
      })
      ..onMouseDown.listen((MouseEvent e) {
        if (_movingEventDiv != null || _resizingEventDiv != null) {
          return;
        }
        
        var y = e.pageY - calendarview.offset.top + calendarview.scrollTop + cursorPosOffsetY;
        var quarters = (y / _zoomLevel.timeFrameHeight).floor();
        var minutes = (quarters % _zoomLevel.hourMultiplier) * _zoomLevel.minuteFactor;
        var hours = (quarters ~/ _zoomLevel.hourMultiplier).floor();
        
        var date = new DateTime.now();
        var start = new DateTime(date.year, date.month, date.day, hours, minutes);
        var end = start.add(new Duration(minutes: _zoomLevel.minuteFactor));
        CalendarEvent newEvent = new CalendarEvent(_calendarView._events.length+2, start, end, '', '');
        
        if (checkObstruction(newEvent) != null) {
          return;
        }
        _calendarView._events.add(newEvent);
        e.preventDefault();
        e.stopPropagation();
        DivElement newEventDiv = _calendarView._renderEvent(newEvent);
        startResizing(null, newEventDiv);
      });
  }
  
  void startResizing(MouseEvent e, DivElement eventDiv) {
    _resizingEventDiv = eventDiv;
    eventDiv.classes.add('resizing');
  }
  
  CalendarEvent checkObstruction(CalendarEvent e) {
    for (CalendarEvent compareEvent in _calendarView._events) {
      if (compareEvent == e) {
        continue;
      }
      if (
          (e.start.compareTo(compareEvent.start) >= 0 && e.start.compareTo(compareEvent.end) < 0)
          || (e.start.compareTo(compareEvent.start) < 0 && e.end.compareTo(compareEvent.start) > 0)
          ) {
        return compareEvent;
      }
        
//        if (
//            (event.start.getTime() >= cmpe.start.getTime() && event.start.getTime() < cmpe.end.getTime())
//                || (event.start.getTime() < cmpe.start.getTime() && event.end.getTime() > cmpe.start.getTime())) {
//            return cmpe;
//        }

    }
    return null;
  }
  
  void trackEvent(CalendarEvent event, DivElement eventDiv, DivElement eventTimeDiv) {
    eventTimeDiv.onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      eventDiv.classes.add('moving');
      _movingEventDiv = eventDiv;
    });
    eventDiv.query('.cal-event-resize').onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      startResizing(e, eventDiv);
    });
  }
}

@CustomTag('tapo-calendar-calendarview')
class CalendarView extends PolymerElement {
  @observable @published DateTime day;
  ZoomLevel _zoomLevel = ZoomLevel.DAY;
  List<CalendarEvent> _events;
  
  CalendarInteractionTracker _interactionTracker;
  
  
  get applyAuthorStyles => true;
  
  void _updateCalcHelpers() {
    
  }
  
  void inserted() {
    super.inserted();
    _updateCalcHelpers();
    print('we have been inserted.');
    if (day == null) {
      day = new DateTime.now();
    }
    // we only care about year/month/day
    day = new DateTime(day.year, day.month, day.day);
    
    calendarWrapper.style.height = "500px";
    _createHtmlTable();
  }
  
  CalendarEvent getEventById(int id) {
    for (CalendarEvent event in _events) {
      if (event.id == id) {
        return event;
      }
    }
    return null;
  }
  
  void set events(List<CalendarEvent> events) {
    _events = events;
    for (CalendarEvent event in _events) {
      _renderEvent(event);
    }
  }
  
  void zoomIn() {
    int pos = ZoomLevel.values.indexOf(_zoomLevel) + 1;
    if (pos >= ZoomLevel.values.length) {
//      pos = 0;
      // can't zoom in any more..
      return;
    }
    updateZoomLevel(ZoomLevel.values[pos]);
  }
  void zoomOut() {
    int pos = ZoomLevel.values.indexOf(_zoomLevel) - 1;
    if (pos < 0) {
//      pos = ZoomLevel.values.length - 1;
      // can't zoom out any more..
      return;
    }
    updateZoomLevel(ZoomLevel.values[pos]);
  }
  
  void updateZoomLevel(ZoomLevel level) {
    var wrapper = calendarWrapper;
    wrapper.classes
      ..remove(_zoomLevel.cssclass)
      ..add(level.cssclass);
    _zoomLevel = level;
    _interactionTracker._zoomLevel = _zoomLevel;
    _updateCalcHelpers();
    for(CalendarEvent event in _events) {
      _updateEvent(event, wrapper.query('div.cal-event[eventid="${event.id}"]'));
    }
  }
  
  void _createTimeGrid(DivElement timegrid) {
    var gridhour = new Element.html('<div class="cal-timegrid-hour" />');
    var gridhalf = new Element.html('<div class="cal-timegrid-hour-half" />');
    var gridfiveminute = new Element.html('<div class="cal-timegrid-five-minute" />');
//    var gridquarter = jQuery('#frame-quarter-hour').children();
//    var gridfive = jQuery('#frame-five-minutes').children();
//    var gridminute = jQuery('#frame-minute').children();

    for(var i in range(1, 24)) {
      var gridline = gridhour.clone(true);
      var gridlinehalf = gridhalf.clone(true);
      gridline.append(gridlinehalf);
      range(1, 6).forEach((j) {
        gridline.append(gridfiveminute.clone(true));
        gridlinehalf.append(gridfiveminute.clone(true));
      });
      timegrid.append(gridline);
    }
    
  }
  
  Element _createAndAppend(Element parent, String html) {
    var fragment = parent.createFragment(html);
    Element el = fragment.nodes.where((e) => e is Element).single;
    parent.append(el);
    return el;
  }
  
  Element get calendarWrapper => getShadowRoot('tapo-calendar-calendarview').query('.calendarview-wrapper');
  
  void _createHtmlTable() {
    var wrapper = calendarWrapper;
    wrapper.append(new Element.html('<div>It works.</div>'));
   
    // table consists of two rows and two columns
    // first row, second column contains time grid (background)
    // second row, first column contains time labels, second column all event contents.
    TableElement table = new Element.html('<table class="cal-table" />') as TableElement;
    var tbody = _createAndAppend(table, "<tbody />") as TableSectionElement;
    var firstRow = _createAndAppend(tbody, "<tr />");
    var firstCell = _createAndAppend(firstRow, '<td class="placeholder-cell" />');
    var timegridCell = _createAndAppend(firstRow, "<td />");
    var contentRow = _createAndAppend(tbody, "<tr />");
    
    var timegridWrapper = _createAndAppend(timegridCell, '<div class="cal-timegrid-wrapper" />');
    var timegrid = _createAndAppend(timegridWrapper, '<div class="cal-timegrid" />');
    _createTimeGrid(timegrid);
    _createTimeColumn(contentRow);
    _createEventsColumn(contentRow);


    wrapper.append(table);
    _interactionTracker = new CalendarInteractionTracker(this, wrapper.parent, contentRow.query('.cal-eventlistwrapper'));
  }
  
  String _formatTimeSegment(int segment) {
    if (segment < 10) {
      return '0${segment}';
    }
    return segment.toString();
  }
  
  void _createTimeColumn(Element contentRow) {
    var timeCol = _createAndAppend(contentRow, '<td class="cal-timecol" />');
    
    for (var i in range(0, 24)) {
//      var timewrapper = jQuery('<div class="cal-timelabel-wrapper" />');
//      var time = jQuery('<div class="cal-timelabel" />'); timewrapper.append(time);
//      var timestr = i < 10 ? '0' + i : i;
//      time.text(timestr + ':00');
//
//      timecol.append(timewrapper);
      var timewrapper = _createAndAppend(timeCol, '<div class="cal-timelabel-wrapper" />');
      var time = _createAndAppend(timewrapper, '<div class="cal-timelabel" />');
      time.text = '${_formatTimeSegment(i)}:00';

    }
  }
  
  /**
   * Formats a date in YYYY-MM-DD
   */
  String _formatDate(DateTime date) =>
    '${date.year}-${_formatTimeSegment(date.month)}-${_formatTimeSegment(date.day)}';
    
  /**
   * Formats a time in HH:MM
   */
  String _formatTimeShort(DateTime time) =>
      '${_formatTimeSegment(time.hour)}:${_formatTimeSegment(time.minute)}';
  
  void _createEventsColumn(TableRowElement contentRow) {
    var eventsColumn = _createAndAppend(contentRow, '<td class="cal-datescol" />');
    var dayColumn = _createAndAppend(eventsColumn, '<div class="cal-eventlistwrapper" />');
    dayColumn.id = "daycol-${_formatDate(day)}";
  }
  
  void _updateEvent(CalendarEvent event, DivElement eventDiv) {
    var eventTimeDiv = eventDiv.query('.cal-event-time');
    var eventLabelDiv = eventDiv.query('.cal-event-label');
    
    var quarters = event.start.hour * _zoomLevel.hourMultiplier + event.start.minute ~/ _zoomLevel.minuteFactor;
    var endquarters = event.end.hour * _zoomLevel.hourMultiplier + event.end.minute ~/ _zoomLevel.minuteFactor;
    
    eventDiv.style.top = '${quarters * _zoomLevel.timeFrameHeight}px';
    eventDiv.style.height = '${(endquarters - quarters) * _zoomLevel.timeFrameHeight}px';
    
    eventTimeDiv.text = '${_formatTimeShort(event.start)} - ${_formatTimeShort(event.end)} id:${event.id}';
    var eventTitleDiv = _createAndAppend(eventTimeDiv, '<div class="cal-event-title" />');
    eventTitleDiv.text = event.title;
  }
  
  DivElement _renderEvent(CalendarEvent event) {
    DivElement dayColumn = calendarWrapper.query('#daycol-${_formatDate(day)}');
    
    var eventDiv = _createAndAppend(dayColumn, '<div class="cal-event" />');
    eventDiv.attributes['eventid'] = '${event.id}';
    var eventTimeDiv = _createAndAppend(eventDiv, '<div class="cal-event-time" />');
    var eventLabelWrapperDiv = _createAndAppend(eventDiv, '<div class="cal-event-label-wrapper" />');
    var eventLabelDiv = _createAndAppend(eventLabelWrapperDiv, '<div class="cal-event-label" />');
    var eventResize = _createAndAppend(eventDiv, '<div class="cal-event-resize" />');
    
    _updateEvent(event, eventDiv);
    
    _interactionTracker.trackEvent(event, eventDiv, eventTimeDiv);
    
    return eventDiv;
  }
}