library calendarview;

import 'package:polymer/polymer.dart';
import 'dart:html';
import 'package:quiver/iterables.dart';
import 'package:logging/logging.dart';
import 'dart:async';


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
  
  
  int posToMinutes(int pos) {
    return pos ~/ timeFrameHeight * minuteFactor;
  }
  int minutesToPos(int minutes) {
    return (minutes / minuteFactor * timeFrameHeight).floor();
  }
}

class EventTheme {
  final String name;
  String baseColor;
  String selectedBaseColor;
  
  final String _rawColor;
  
  EventTheme(this.name, this._rawColor, [this.baseColor = null]) {
    if (this.baseColor == null) {
      this.baseColor = _lighten(_rawColor, 30);
    }
    this.selectedBaseColor = _rawColor;
  }
  
  String get mainBgColor => _lighten(_rawColor, 50);
  String get selectedBgColor => _lighten(_rawColor, 30);
  
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
  
  static final BLUE = new EventTheme('blue', '#5555ff');
  static final RED = new EventTheme('red', '#ff5555');
  static final GREEN = new EventTheme('green', '#006400');
  static final YELLOW = new EventTheme('yellow', '#a6a600', '#d4d400');
  static final ORANGE = new EventTheme('orange', '#FF6633');
  static final BROWN = new EventTheme('brown', '#B8860B');
  static final PURPLE = new EventTheme('purple', '#6733DD');
  static final TURQUOISE = new EventTheme('torquoise', '#46D6DB');
  
  static final List<EventTheme> themes = [BLUE, RED, GREEN, YELLOW, ORANGE, BROWN, PURPLE, TURQUOISE];
}

class CalendarEvent extends Observable {
  int id;
  @observable DateTime start;
  @observable DateTime end;
  @observable String title;
  @observable String description;
  @observable EventTheme theme = EventTheme.BLUE;
  @observable bool isInProgress = false;
  int _marginLeft = 0;
  DateTime _paddedStart;
  DateTime _paddedEnd;
  
  CalendarEvent(this.id, this.start, this.end, this.title, this.description);
  
  void _addPadding(Duration padding) {
    _paddedStart = start.subtract(padding);
    if (end == null) {
      _paddedEnd = start.add(padding);
    } else {
      _paddedEnd = end.add(padding);
    }
  }
}

class CalendarAnnotationActionSelectedDetail {
  CalendarAnnotationAction action;
  CalendarAnnotation annotation;
  CalendarAnnotationActionSelectedDetail(this.action, this.annotation);
}

class CalendarAnnotationAction {
  String key;
  String label;
  String href;
  String iconsrc;
  CalendarAnnotationAction(this.key, this.label, {this.href, this.iconsrc});
  
  Element createActionElement(CalendarAnnotation annotation) {
    var a = this;
    var el = new AnchorElement(href: "#")..classes.add('cal-annotation-action');
    if (a.iconsrc != null) {
      el.append(new ImageElement(src: a.iconsrc, width: 10, height: 10));
    } else {
      el.text=a.label;
    }
    if (a.href != null) {
      el.target = '_blank';
      el.href = a.href;
    } else {
      el.onClick.listen((e){
        e.preventDefault();
        e.stopPropagation();
        el.dispatchEvent(new CustomEvent(
            'annotationactionselected',
            detail: new CalendarAnnotationActionSelectedDetail(a, annotation)));
      });
    }
    return el;
  }
}

class CalendarAnnotation extends CalendarEvent {
  List<CalendarAnnotationAction> actions;
  
  CalendarAnnotation(int id, DateTime start, DateTime end, String title, String description,
      {this.actions: null}) :
    super(id, start, end, title, description);
  
}

class CalendarInteractionTracker {
  DivElement _eventListWrapperDiv;
  CalendarView _calendarView;
  
  /// div which is currently resizing. (is null if the user is not resizing an element right now.)
  DivElement _resizingEventDiv;
  DivElement _movingEventDiv;
  ZoomLevel _zoomLevel;
  int cursorPosOffsetY = 0;

  CalendarInteractionTracker(this._calendarView, DivElement calendarview, this._eventListWrapperDiv) {
    if (_calendarView == null) {
      throw new Exception('_calendarView must not be null.');
    }
    _zoomLevel = _calendarView._zoomLevel;
    _eventListWrapperDiv
      ..onMouseMove.listen((MouseEvent e) {
        var eventdiv = _movingEventDiv != null ? _movingEventDiv : _resizingEventDiv;
        if (eventdiv == null && !_calendarView._isToday) {
            return;
        }
//        print('moving event.');
        var y = getRelativeYPos(e, calendarview);
//        var y = e.page.y - calendarview.offset.top + calendarview.scrollTop + cursorPosOffsetY;
        var quarters = (y / _zoomLevel.timeFrameHeight).floor();
        var minutes = (quarters % _zoomLevel.hourMultiplier) * _zoomLevel.minuteFactor;
        var hours = (quarters ~/ _zoomLevel.hourMultiplier).floor();
        
        if (eventdiv == null) {
          if (!_calendarView._allowEditing(hours, minutes)) {
            _eventListWrapperDiv.classes.add('unavailable');
          } else {
            _eventListWrapperDiv.classes.remove('unavailable');
          }
          return;
        }
        
        CalendarEvent event = _calendarView.getEventById(int.parse(eventdiv.attributes['eventid']));
        
        DateTime now = _calendarView._floorToMinute(new DateTime.now());

        if (_resizingEventDiv != null) {
          // user is resizing event.
          var today = _calendarView._day;
          event.end = new DateTime(today.year, today.month, today.day, hours, minutes);
          if (_calendarView._onlyHistoryEdit) {
            if (event.end.isAfter(now)) {
              event.end = now;
            }
          }
          
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
          if (_calendarView._onlyHistoryEdit) {
            if (event.end.isAfter(now)) {
              event.end = now;
              event.start = now.subtract(diff);
            }
          }
          
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
        
        var y = getRelativeYPos(e, calendarview);
        var quarters = (y / _zoomLevel.timeFrameHeight).floor();
        var minutes = (quarters % _zoomLevel.hourMultiplier) * _zoomLevel.minuteFactor;
        var hours = (quarters ~/ _zoomLevel.hourMultiplier).floor();
        
        if (!_calendarView._allowEditing(hours, minutes)) {
          e.stopPropagation(); e.preventDefault();
          // TODO tell the user, that he can't add events in the future?
          return;
        }
        
        var date = _calendarView._day;
        var start = new DateTime(date.year, date.month, date.day, hours, minutes);
        var end = start.add(new Duration(minutes: _zoomLevel.minuteFactor));
        _logger.info('Creating new event at ${start}');
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
  
  int getRelativeYPos(MouseEvent e, DivElement calendarview) {
    Element tmp = calendarview;
    int offsetTop = 0;
    while (tmp != null) {
      offsetTop += tmp.offset.top;
      tmp = tmp.offsetParent;
    }
    return e.page.y - offsetTop + calendarview.scrollTop + cursorPosOffsetY;
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
      if (event.isInProgress) {
        return;
      }
      _calendarView.updateSelectedEvent(event);
    });
    eventTimeDiv.onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      if (event.isInProgress) {
        return;
      }
      _calendarView.updateSelectedEvent(event);
      eventDiv.classes.add('moving');
      _movingEventDiv = eventDiv;
    });
    eventDiv.querySelector('.cal-event-resize').onMouseDown.listen((MouseEvent e) {
      e.preventDefault();
      e.stopPropagation();
      if (event.isInProgress) {
        return;
      }
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
  /// calendar events which are just shown as "annotations" (small dots on the calendar.)
  List<CalendarEvent> _annotations = [];
  @observable @published CalendarEvent selectedevent = null;
  CalendarListener listener = null;
  bool _isToday;
  bool _isFuture;
  Timer _updateNowTimer;
  /// defines that only history can be modified, not the future.
  bool _onlyHistoryEdit = true;
  DivElement _dayColumn = null;
  @observable @published int count = 0;
  
  CalendarInteractionTracker _interactionTracker;
  
  
  get applyAuthorStyles => true;
  
  CalendarView.created() : super.created() {
    onPropertyChange(this, #selectedevent, () {
      print('CalendarView: onPropertyChange for selectedevent.');
    });
  }
  
  void _updateCalcHelpers() {
    
  }
  
  void updateSelectedEvent(CalendarEvent event) {
    if (selectedevent == event) {
      // nothing to do..
      return;
    }
    print('changed selectedevent');
    var oldEvent = selectedevent;
    selectedevent = event;
    count++;
    if (oldEvent != null) {
      _updateEvent(oldEvent, null);
    }
    if (selectedevent != null) {
      _updateEvent(selectedevent, null);
    }
  }
  
  @observable @published void set day (DateTime date) {
    _day = date;
    _logger.fine("setting day to ${_day}");
    _dayStart = new DateTime(date.year, date.month, day.day);
    _dayEnd = _dayStart.add(const Duration(days: 1)).subtract(const Duration(seconds: 1));
    var now = new DateTime.now();
    _isToday = now.year == _day.year && now.month == _day.month && now.day == _day.day;
    _isFuture = now.isBefore(_dayStart);
    _updateNowRestrictions();
    _updateNowLine();
  }
  @observable @published DateTime get day => _day;
  bool get isToday => _isToday;
  
  @override
  void attached() {
    super.attached();
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
  
  void set annotations(List<CalendarEvent> annotations) {
    _annotations = annotations;
    // make sure annotations are ordered by time, and see if there are any obstructions.
    Duration padding = const Duration(minutes: 5);
    _annotations.forEach((e) => e._addPadding(padding));
    _annotations.sort((a, b) => a.start.compareTo(b.start));

    // we now have to check if some annotations are at the same time as others.
    var annotationStack = new List<CalendarEvent>();
    for (CalendarEvent a in _annotations) {
      if (annotationStack.isEmpty) {
        annotationStack.add(a);
        continue;
      }
      
      int i = 0;
      bool foundPosition = false;
      // each entry in the stack is one "column" now we simply check where we have enough room, and assign it..
      for (CalendarEvent stackElement in annotationStack) {
        if (stackElement._paddedEnd == null || stackElement._paddedEnd.isBefore(a._paddedStart)) {
            a._marginLeft = i;
            annotationStack[i] = a;
            foundPosition = true;
            break;
//          }
        }
        i++;
      }
      if (!foundPosition) {
        a._marginLeft = annotationStack.length;
        annotationStack.add(a);
      }
    }
    if (day != null) {
      _renderAllAnnotations();
    }
  }
  
  void _renderAllEvents() {
    this.getShadowRoot('tapo-calendar-calendarview')
      .querySelectorAll(".cal-event")
        .forEach((Element el) => el.remove());
    _events.forEach((event) => _renderEvent(event));
  }
  
  void _renderAllAnnotations() {
    this.getShadowRoot('tapo-calendar-calendarview')
      .querySelectorAll('.cal-annotation')
        .forEach((Element el) => el.remove());
    _annotations.forEach((event) { _renderAnnotation(event); });
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
  
  void scrollTo(int hours) {
    int pos = _zoomLevel.minutesToPos(hours * 60);
    var wrapper = calendarWrapper;
    wrapper.parent.scrollTop = pos;
  }
  
  void updateZoomLevel(ZoomLevel level) {
    var wrapper = calendarWrapper;
    if (wrapper.parent.classes.contains('inzoomanimation')) {
      return;
    }
    var scrollPos = wrapper.parent.scrollTop;
    var height = 500;
    int centerMinutes = _zoomLevel.posToMinutes(scrollPos + (height ~/ 2));
    wrapper.style.top = '-${scrollPos}px';
    wrapper.parent.scrollTop = 0;
    wrapper.parent.classes.add('inzoomanimation');
    wrapper.classes
      ..remove(_zoomLevel.cssclass)
      ..add(level.cssclass);
    _zoomLevel = level;
    _interactionTracker._zoomLevel = _zoomLevel;
    _updateCalcHelpers();
    
    int newCenterPos = _zoomLevel.minutesToPos(centerMinutes);
    int newScrollPos = max([newCenterPos - height ~/ 2, 0]);
    wrapper.style.top = "-${newScrollPos}px";
    print("Old pos: ${scrollPos} - newPos: ${newScrollPos}");
    StreamSubscription subscription = null;
    _updateNowTimer.cancel();
    var nowLine = wrapper.querySelector('.cal-now');
    if (nowLine != null) {
      nowLine.remove();
    }
    var endTransition = () {
      _logger.finer('we got transitionend event. top: ${wrapper.style.top} / newScrollPos: ${newScrollPos} / oldScrollPos: ${scrollPos} / current scrollTop: ${wrapper.parent.scrollTop} ');
      wrapper.parent.classes.remove('inzoomanimation');
      wrapper.style.top = '0px';
      wrapper.parent.scrollTop = newScrollPos;
      _updateNowLine();
      subscription.cancel();
      subscription = null;
    };
    subscription = wrapper.onTransitionEnd.listen((event) => endTransition);
    new Timer(const Duration(seconds: 2), (){
      if (subscription != null) {
        _logger.finer('Got no transition end event - forcing end.');
        endTransition();
      }
    });
    
    for(CalendarEvent event in _events) {
      _updateEvent(event, wrapper.querySelector('div.cal-event[eventid="${event.id}"]'));
    }
    _annotations.forEach((annotation) =>
        _updateAnnotation(
            annotation,
            wrapper.querySelector('div.cal-annotation[annotationid="${annotation.id}"]')));
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
  
  Element get calendarWrapper => getShadowRoot('tapo-calendar-calendarview').querySelector('.calendarview-wrapper');
  
  void _createHtmlTable() {
    var wrapper = calendarWrapper;
   
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
    _interactionTracker = new CalendarInteractionTracker(this, wrapper.parent, contentRow.querySelector('.cal-eventlistwrapper'));
    _updateNowRestrictions();
    _updateNowLine();
  }
  
  void _updateNowRestrictions() {
    var listWrapper = calendarWrapper.querySelector('.cal-eventlistwrapper');
    if (listWrapper == null) {
      _logger.finer('listWrapper not defined. doing nothing.');
      return;
    }
    _logger.fine('updating now restrictions.');
    
    if (_isFuture && !_isToday) {
      listWrapper.classes.add('unavailable');
    } else {
      listWrapper.classes.remove('unavailable');
    }
  }
  
  void _updateNowLine([Timer timer = null]) {
    var listWrapper = calendarWrapper;
    if (listWrapper == null) {
      return;
    }
    var calNow = listWrapper.querySelector('.cal-now');
    if (!_isToday) {
      if (calNow != null) {
        calNow.remove();
      }
      return;
    }
    if (calNow == null) {
      var eventListWrapper = listWrapper.querySelector('.cal-eventlistwrapper');
      if (eventListWrapper == null) {
        return;
      }
      calNow = _createAndAppend(eventListWrapper, '<div class="cal-now" />');
    }
    var now = new DateTime.now();
//    var quarters = now.getHours() * TAPO.CalendarView.HOURMULTIPLIER + now.getMinutes() / TAPO.CalendarView.MINUTEFACTOR;
    
    var quarters = now.hour * _zoomLevel.hourMultiplier + now.minute ~/ _zoomLevel.minuteFactor;
    calNow.style.top = '${quarters * _zoomLevel.timeFrameHeight}px';
    if (_updateNowTimer == null || !_updateNowTimer.isActive) {
      _updateNowTimer = new Timer(const Duration(seconds: 2), _updateNowLine);
    }
    
    try {
      var event = _events.where((e) => e.isInProgress).first;
      event.end = now;
      if (event.end.difference(event.start).inMinutes < 15) {
        event.end = event.start.add(new Duration(minutes: 15));
      }
      _updateEvent(event);
    } catch (e) {
      // no in progress event. ignore it.
    }
  }
  
  String _formatTimeSegment(int segment) {
    if (segment < 10) {
      return '0${segment}';
    }
    return segment.toString();
  }
  
  bool _allowEditing(int hours, int minutes) {
    if (!_isToday) {
      return true;
    }
    // TODO: i'm pretty sure it would be faster to just compare the integers :)
    var tmpNow = new DateTime.now();
    var tmpCmp = new DateTime(tmpNow.year, tmpNow.month, tmpNow.day, hours, minutes);
    return tmpCmp.isBefore(tmpNow);
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
    _dayColumn = dayColumn;
    dayColumn.id = "daycol-${_formatDate(day)}";
  }
  
  void _updateEvent(CalendarEvent event, [DivElement eventDiv = null]) {
    if (eventDiv == null) {
      eventDiv = calendarWrapper.querySelector('div.cal-event[eventid="${event.id}"]');
      if (eventDiv == null) {
        _logger.severe('Unable to find event div for event id ${event.id}');
      }
    }
    var eventTimeDiv = eventDiv.querySelector('.cal-event-time');
    var eventTimeLabel = eventTimeDiv.querySelector('.cal-event-time-label');
    var eventLabelDiv = eventDiv.querySelector('.cal-event-label');
    var eventResizeDiv = eventDiv.querySelector('.cal-event-resize');
    
    if (event == selectedevent) {
      eventDiv.style.borderColor = event.theme.selectedBaseColor;
      eventDiv.style.backgroundColor = event.theme.selectedBgColor;
      eventTimeDiv.style.backgroundColor = event.theme.selectedBaseColor;
    } else {
      eventDiv.style.borderColor = event.theme.baseColor;
      eventDiv.style.backgroundColor = event.theme.mainBgColor;
      eventTimeDiv.style.backgroundColor = event.theme.baseColor;
    }
    eventResizeDiv.style.backgroundColor = event.theme.baseColor;
    
    var startDate = max([event.start, _dayStart]);
    var endDate = min([event.end, _dayEnd]);
    var quarters = startDate.hour * _zoomLevel.hourMultiplier + startDate.minute ~/ _zoomLevel.minuteFactor;
    var endquarters = endDate.hour * _zoomLevel.hourMultiplier + endDate.minute ~/ _zoomLevel.minuteFactor;
    
    eventDiv.style.top = '${quarters * _zoomLevel.timeFrameHeight}px';
    eventDiv.style.height = '${(endquarters - quarters) * _zoomLevel.timeFrameHeight}px';
    
    String startStr = _formatTimeShort(event.start);
    String endStr = _formatTimeShort(event.end);
    if (event.start.isBefore(_dayStart)) {
      startStr = '${_formatDate(event.start)} ${startStr}';
    }
    if (event.end.isAfter(_dayEnd)) {
      endStr = '${_formatDate(event.start)} ${endStr}';
    }
    
    eventTimeLabel.text = '${startStr} - ${endStr} - ${event.title}';
//    var eventTitleDiv = _createAndAppend(eventTimeDiv, '<span class="cal-event-title" />');
//    eventTitleDiv.text = event.title;
  }
  
  DateTime _floorToMinute(DateTime date) {
    return new DateTime(date.year, date.month, date.day, date.hour, date.minute);
  }
  
  DivElement _renderEvent(CalendarEvent event) {
    DivElement dayColumn = _dayColumn; //calendarWrapper.querySelector('#daycol-${_formatDate(day)}');
    
    var eventDiv = _createAndAppend(dayColumn, '<div class="cal-event" />');
    eventDiv.attributes['eventid'] = '${event.id}';
    if (event.isInProgress) {
      eventDiv.classes.add('type-inprogress');
    }
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
    if (event.isInProgress) {
      removeLink.remove();
    } else {
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
    }
    
    _updateEvent(event, eventDiv);
    
    _interactionTracker.trackEvent(event, eventDiv, eventTimeDiv);
    
    var changed = () => _updateEvent(event, eventDiv);
    onPropertyChange(event, #title, changed);
    onPropertyChange(event, #description, changed);
    
    return eventDiv;
  }
  
  void _updateAnnotation(CalendarEvent annotation, DivElement eventDiv) {
    var startDate = max([annotation.start, _dayStart]);
    var quarters = startDate.hour * _zoomLevel.hourMultiplier + startDate.minute ~/ _zoomLevel.minuteFactor;
    
    eventDiv.style.top = '${quarters * _zoomLevel.timeFrameHeight}px';
    eventDiv.style.marginLeft = '${annotation._marginLeft * 6}px';
    if (annotation.end != null) {
      var indicatorDiv = eventDiv.querySelector(".indicator");
      var endDate = min([annotation.end, _dayEnd]);
      var endquarters = endDate.hour * _zoomLevel.hourMultiplier + endDate.minute ~/ _zoomLevel.minuteFactor;
      var height = (endquarters - quarters) * _zoomLevel.timeFrameHeight;
      if (height > 10) {
        eventDiv.classes.add("cal-annotation-duration");
        indicatorDiv.style.height = '${height}px';
      } else {
        indicatorDiv.style.height = '';
        eventDiv.classes.remove("cal-annotation-duration");
      }
    } else {
      eventDiv.classes.remove("cal-annotation-duration");
    }
  }
  
  
  DivElement _renderAnnotation(CalendarEvent annotation) {
    DivElement dayColumn = _dayColumn; //calendarWrapper.querySelector('#daycol-${_formatDate(day)}');
    
    var eventDiv = _createAndAppend(dayColumn, '<div class="cal-annotation" />');
    var tooltipDiv = _createAndAppend(eventDiv, '<div class="cal-tooltip" />');
    var indicatorDiv = _createAndAppend(eventDiv, '<div class="indicator" />');
    eventDiv.attributes['annotationid'] = '${annotation.id}';
    var endlabel = annotation.end == null ? '' : ' - ${_formatTimeShort(annotation.end)}';
    var durationStr = '';
    if (annotation.end != null) {
      Duration duration = annotation.end.difference(annotation.start);
      if (duration.inMinutes > 0) {
        durationStr = " (${duration.inMinutes} Minutes)";
      } else {
        durationStr = " (${duration.inSeconds} Seconds)";
      }
    }
    eventDiv.onMouseDown.listen((e) => e.stopPropagation());
    tooltipDiv.text = '${_formatTimeShort(annotation.start)}$endlabel: ${annotation.title}${durationStr}';
    if (annotation is CalendarAnnotation && annotation.actions != null) {
      tooltipDiv.children.addAll(annotation.actions.map((action) => action.createActionElement(annotation)));
    }
    indicatorDiv.onMouseDown.listen((e) {
      dayColumn.querySelectorAll('.cal-annotation-active')
        .forEach((Element e) => e.classes.remove('cal-annotation-active'));
      eventDiv.classes.add('cal-annotation-active');
      new Timer(const Duration(seconds: 10), (){
        eventDiv.classes.remove('cal-annotation-active');
      });
    });
    
    _updateAnnotation(annotation, eventDiv);
    
    return eventDiv;
  }

}