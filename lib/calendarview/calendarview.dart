library calendarview;

import 'package:polymer/polymer.dart';
import 'dart:html';
import 'package:quiver/iterables.dart';
import 'package:logging/logging.dart';


Logger _logger = new Logger('tapo.calendar.calendarview');


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

class EventTheme {
  final String name;
  final String baseColor;
  
  const EventTheme(this.name, this.baseColor);
  
  String get mainBgColor => _lighten(baseColor, 50);
  String get selectedBgColor => _lighten(baseColor, 30);
  
  String _lighten(String hex, int percent) {
    // http://stackoverflow.com/a/13542669/109219
    int color = int.parse(hex.substring(1), radix: 16);
    var amt = (2.55 * percent).round();
    int r = (color >> 16) + amt;
    int b = (color >> 8 & 0x00FF) + amt;
    int g = (color & 0x0000FF) + amt;
    r = min([255, max([0,r])]);
    b = min([255, max([0,b])]);
    g = min([255, max([0,g])]);
    int resultColor = 0x1000000 + r*0x10000 + b*0x100 + g;
    return '#${resultColor.toRadixString(16).substring(1)}';
//    return "";
    /*
     *     var num = parseInt(color,16),
    amt = Math.round(2.55 * percent),
    R = (num >> 16) + amt,
    B = (num >> 8 & 0x00FF) + amt,
    G = (num & 0x0000FF) + amt;
    return (0x1000000 + (R<255?R<1?0:R:255)*0x10000 + (B<255?B<1?0:B:255)*0x100 + (G<255?G<1?0:G:255)).toString(16).slice(1);
     * 
     */
  }
  
  static const BLUE = const EventTheme('blue', '#5555ff');
  static const RED = const EventTheme('red', '#ff5555');
  static const GREEN = const EventTheme('green', '#006400');
  static const YELLOW = const EventTheme('yellow', '#FFD700');
  static const ORANGE = const EventTheme('orange', '#FF6633');
  static const BROWN = const EventTheme('brown', '#B8860B');
  static const PURPLE = const EventTheme('purple', '#6733DD');
  static const TURQUOISE = const EventTheme('torquoise', '#46D6DB');
  
  static const List<EventTheme> themes = const [BLUE, RED, GREEN, YELLOW, ORANGE, BROWN, PURPLE, TURQUOISE];
}

class CalendarEvent extends Observable {
  int id;
  @observable DateTime start;
  @observable DateTime end;
  @observable String title;
  @observable String description;
  @observable EventTheme theme = EventTheme.BLUE;
  
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
    if (_calendarView == null) {
      throw new Exception('_calendarView must not be null.');
    }
    _zoomLevel = _calendarView._zoomLevel;
    _eventListWrapperDiv
      ..onMouseMove.listen((MouseEvent e) {
        var eventdiv = _movingEventDiv != null ? _movingEventDiv : _resizingEventDiv;
        if (eventdiv == null) {
            return;
        }
//        print('moving event.');
        var y = e.page.y - calendarview.offset.top + calendarview.scrollTop + cursorPosOffsetY;
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
        CalendarEvent event = null;
        if (_movingEventDiv != null) {
          event = _calendarView.getEventById(int.parse(_movingEventDiv.attributes['eventid']));
          _movingEventDiv.classes.remove('moving');
          _movingEventDiv = null;
        }
        if (_resizingEventDiv != null) {
          event = _calendarView.getEventById(int.parse(_resizingEventDiv.attributes['eventid']));
          _resizingEventDiv.classes.remove('resizing');
          _resizingEventDiv = null;
        }
        if (event != null && _calendarView.listener != null) {
          _calendarView.listener.changedEventTimes(event);
        }
      })
      ..onMouseDown.listen((MouseEvent e) {
        if (_movingEventDiv != null || _resizingEventDiv != null) {
          return;
        }
        
        var y = e.page.y - calendarview.offset.top + calendarview.scrollTop + cursorPosOffsetY;
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
        if (_calendarView.listener != null) {
          _calendarView.listener.createdEvent(newEvent);
        }
        _calendarView.updateSelectedEvent(newEvent);
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
    eventDiv.onMouseDown.listen((MouseEvent e){
      _calendarView.updateSelectedEvent(event);
    });
    eventTimeDiv.onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      _calendarView.updateSelectedEvent(event);
      eventDiv.classes.add('moving');
      _movingEventDiv = eventDiv;
    });
    eventDiv.querySelector('.cal-event-resize').onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      _calendarView.updateSelectedEvent(event);
      startResizing(e, eventDiv);
    });
  }
}

/**
 * Simple listener for events. Users don't need to listen on change requests to
 * CalendarEvent properties, as they are notified in this listener.
 * TODO: think about what's better.. :-) observing changes in CalendarEvent.xxx seems more dart/polymer-ish
 */
abstract class CalendarListener {
  void createdEvent(CalendarEvent event);
  void removedEvent(CalendarEvent event);
  void changedEventTimes(CalendarEvent event);
  void changedEventDescription(CalendarEvent event);
}

@CustomTag('tapo-calendar-calendarview')
class CalendarView extends PolymerElement {
  DateTime _day;
  DateTime _dayStart;
  DateTime _dayEnd;
  ZoomLevel _zoomLevel = ZoomLevel.DAY;
  List<CalendarEvent> _events = [];
  @observable @published CalendarEvent selectedevent = null;
  CalendarListener listener = null;
  
  CalendarInteractionTracker _interactionTracker;
  
  
  get applyAuthorStyles => true;
  
  CalendarView.created() : super.created();
  
  void _updateCalcHelpers() {
    
  }
  
  void updateSelectedEvent(CalendarEvent event) {
    if (selectedevent == event) {
      // nothing to do..
      return;
    }
    var oldEvent = selectedevent;
    selectedevent = event;
    if (oldEvent != null) {
      _updateEvent(oldEvent, null);
    }
    if (selectedevent != null) {
      _updateEvent(selectedevent, null);
    }
  }
  
  @observable @published void set day (DateTime date) {
    _logger.fine("setting day to ${_day}");
    _day = date;
    _dayStart = new DateTime(date.year, date.month, day.day);
    _dayEnd = _dayStart.add(new Duration(days: 1));
  }
  @observable @published DateTime get day => _day;
  
  void enteredView() {
    super.enteredView();
    _updateCalcHelpers();
    _logger.finer('we have been inserted.');
//    if (day == null) {
//      day = new DateTime.now();
//    }
    // we only care about year/month/day
    day = new DateTime.now();
    
    calendarWrapper.style.height = "500px";
    _createHtmlTable();
    if (_events != null) {
      _events.forEach((e) { _renderEvent(e); });
    }
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
    _logger.fine("Events set. ${events.length}");
    _events = events;
    if (day != null) {
      _renderAllEvents();
    }
  }
  
  void _renderAllEvents() {
    this.getShadowRoot('tapo-calendar-calendarview')
      .querySelectorAll(".cal-event")
        .forEach((Element el) => el.remove());
    _events.forEach((event) => _renderEvent(event));
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
      _updateEvent(event, wrapper.querySelector('div.cal-event[eventid="${event.id}"]'));
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
  
  void _updateEvent(CalendarEvent event, [DivElement eventDiv = null]) {
    if (eventDiv == null) {
      eventDiv = calendarWrapper.querySelector('div.cal-event[eventid="${event.id}"]');
    }
    var eventTimeDiv = eventDiv.querySelector('.cal-event-time');
    var eventTimeLabel = eventTimeDiv.querySelector('.cal-event-time-label');
    var eventLabelDiv = eventDiv.querySelector('.cal-event-label');
    var eventResizeDiv = eventDiv.querySelector('.cal-event-resize');
    
    eventDiv.style.borderColor = event.theme.baseColor;
    if (event == selectedevent) {
      eventDiv.style.backgroundColor = event.theme.selectedBgColor;
    } else {
      eventDiv.style.backgroundColor = event.theme.mainBgColor;
    }
    eventResizeDiv.style.backgroundColor = event.theme.baseColor;
    eventTimeDiv.style.backgroundColor = event.theme.baseColor;
    
    var startDate = event.start;
    if (startDate.compareTo(_dayStart) < 0) {
      startDate = _dayStart;
    }
    var quarters = startDate.hour * _zoomLevel.hourMultiplier + startDate.minute ~/ _zoomLevel.minuteFactor;
    var endquarters = event.end.hour * _zoomLevel.hourMultiplier + event.end.minute ~/ _zoomLevel.minuteFactor;
    
    eventDiv.style.top = '${quarters * _zoomLevel.timeFrameHeight}px';
    eventDiv.style.height = '${(endquarters - quarters) * _zoomLevel.timeFrameHeight}px';
    
    eventTimeLabel.text = '${_formatTimeShort(event.start)} - ${_formatTimeShort(event.end)} - ${event.title}';
//    var eventTitleDiv = _createAndAppend(eventTimeDiv, '<span class="cal-event-title" />');
//    eventTitleDiv.text = event.title;
  }
  
  DivElement _renderEvent(CalendarEvent event) {
    DivElement dayColumn = calendarWrapper.query('#daycol-${_formatDate(day)}');
    
    var eventDiv = _createAndAppend(dayColumn, '<div class="cal-event" />');
    eventDiv.attributes['eventid'] = '${event.id}';
    var eventTimeDiv = _createAndAppend(eventDiv, '<div class="cal-event-time"><span class="cal-event-time-label"></span></div>');
    var eventLabelWrapperDiv = _createAndAppend(eventDiv, '<div class="cal-event-label-wrapper" />');
    InputElement eventLabelInput = _createAndAppend(eventLabelWrapperDiv, '<input type="text" class="cal-event-label" />');
    var eventResize = _createAndAppend(eventDiv, '<div class="cal-event-resize" />');
    //        eventtime.append(jQuery('<a style="float: right;" />').append(jQuery('<img src="'+TAPO.STATIC_URL+'saas/images/openerp/listgrid/delete_inline.gif" />')
    var removeLink = _createAndAppend(eventTimeDiv, '<a class="delete-inline-wrapper" />');
    var removeIcon = _createAndAppend(removeLink , '<i class="delete-inline" />');
    
    eventLabelInput.onFocus.listen((e){
      if (!eventLabelInput.classes.contains('editing')) {
        calendarWrapper.querySelectorAll('.cal-event-label.editing input').forEach((el){el.blur();});
//        jQuery('body').prepend('<div id="overlay" />');
        eventLabelInput.classes.add('editing');
        return null;
      }
    });
    eventLabelInput.value = event.description;
    eventLabelInput.onBlur.listen((e){
      event.description = eventLabelInput.value;
      _logger.finer('Changed event description to ${eventLabelInput.value}');
      eventLabelInput.classes.remove('editing');
      if (listener != null) {
        listener.changedEventDescription(event);
      }
    });
    eventLabelInput.onKeyDown.listen((KeyboardEvent e) {
      if (e.which == 13) {
        eventLabelInput.blur();
      }
    });
    removeIcon.onMouseDown.listen((e) {
      e.preventDefault();
      e.stopPropagation();
    });
    removeIcon.onClick.listen((e){
      print('clicked removeLink.');
      e.preventDefault();
      e.stopPropagation();
      _events.remove(event);
      if (selectedevent == event) {
        updateSelectedEvent(null);
      }
      eventDiv.remove();

      if (listener != null) {
        listener.removedEvent(event);
      }
    });
    
    _updateEvent(event, eventDiv);
    
    _interactionTracker.trackEvent(event, eventDiv, eventTimeDiv);
    
    var changed = () => _updateEvent(event, eventDiv);
    onPropertyChange(event, #title, changed);
    onPropertyChange(event, #description, changed);
    
    return eventDiv;
  }
}