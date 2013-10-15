import 'package:polymer/polymer.dart';
import 'dart:html';
import 'package:quiver/iterables.dart';

class ZoomLevel {
  final String cssclass;
  const ZoomLevel(this.cssclass);
  
  static const DAY = const ZoomLevel('zoom-day');
  static const QUARTER_HOUR = const ZoomLevel('zoom-quarter-hour');
  static const FIVE_MINUTES = const ZoomLevel('zoom-five-minutes');
  static const MINUTE = const ZoomLevel('zoom-minute');
  
  static const List<ZoomLevel> values = const [DAY, QUARTER_HOUR, FIVE_MINUTES, MINUTE];
}

class Event {
  int id;
  DateTime start;
  DateTime end;
  String title;
  String description;
  
  Event(this.id, this.start, this.end, this.title, this.description);
}

@CustomTag('tapo-calendar-calendarview')
class CalendarView extends PolymerElement {
  @observable @published DateTime day;
  ZoomLevel _zoomLevel = ZoomLevel.DAY;
  List<Event> _events;
  
  /// height of one hour. must also be configured in css.
  int _heightHour = 60;
  /// the smallest editable/showable time duration in minutes. (15 means only quarter hours can be selected)
  int _minuteFactor = 15;
  /// smallest editable unit * _hourMultiplier = 60
  int _hourMultiplier;
  /// height of the smallest editable unites.
  int _timeFrameHeight;
  
  
  get applyAuthorStyles => true;
  
  void _updateCalcHelpers() {
    switch(_zoomLevel) {
      case ZoomLevel.DAY:
        _heightHour = 60;
        _minuteFactor = 15;
        break;
      case ZoomLevel.QUARTER_HOUR:
        _heightHour = 60*4;
        _minuteFactor = 5;
        break;
      case ZoomLevel.FIVE_MINUTES:
        _heightHour = 60 * 16;
        _minuteFactor = 15;
        break;
      case ZoomLevel.MINUTE:
        _heightHour = 60*64;
        _minuteFactor = 1;
        break;
    }
    _hourMultiplier = 60 ~/ _minuteFactor;
    _timeFrameHeight = _heightHour ~/ _hourMultiplier;
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
  
  void set events(List<Event> events) {
    _events = events;
    for (Event event in _events) {
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
    _updateCalcHelpers();
    for(Event event in _events) {
      _updateEvent(event, wrapper.query('div.cal-event[eventid="${event.id}"]'));
    }
  }
  
  void _createTimeGrid(DivElement timegrid) {
    var gridhour = new Element.html('<div class="cal-timegrid-hour" />');
    var gridhalf = new Element.html('<div class="cal-timegrid-hour-half" />');
//    var gridquarter = jQuery('#frame-quarter-hour').children();
//    var gridfive = jQuery('#frame-five-minutes').children();
//    var gridminute = jQuery('#frame-minute').children();

    for(var i in range(1, 24)) {
      var gridline = gridhour.clone(true);
      gridline.append(gridhalf.clone(true));
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
    wrapper.append(new Element.html('<div>It works.</div>'));
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
  
  void _updateEvent(Event event, DivElement eventDiv) {
    var eventTimeDiv = eventDiv.query('.cal-event-time');
    var eventLabelDiv = eventDiv.query('.cal-event-label');
    
    var quarters = event.start.hour * _hourMultiplier + event.start.minute ~/ _minuteFactor;
    var endquarters = event.end.hour * _hourMultiplier + event.end.minute ~/ _minuteFactor;
    
    eventDiv.style.top = '${quarters * _timeFrameHeight}px';
    eventDiv.style.height = '${(endquarters - quarters) * _timeFrameHeight}px';
    
    eventTimeDiv.text = '${_formatTimeShort(event.start)} - ${_formatTimeShort(event.end)}';
    var eventTitleDiv = _createAndAppend(eventTimeDiv, '<div class="cal-event-title" />');
    eventTitleDiv.text = event.title;
  }
  
  void _renderEvent(Event event) {
    DivElement dayColumn = calendarWrapper.query('#daycol-${_formatDate(day)}');
    
    var eventDiv = _createAndAppend(dayColumn, '<div class="cal-event" />');
    eventDiv.attributes['eventid'] = '${event.id}';
    var eventTimeDiv = _createAndAppend(eventDiv, '<div class="cal-event-time" />');
    var eventLabelWrapperDiv = _createAndAppend(eventDiv, '<div class="cal-event-label-wrapper" />');
    var eventLabelDiv = _createAndAppend(eventLabelWrapperDiv, '<div class="cal-event-label" />');
    var eventResize = _createAndAppend(eventDiv, '<div class="cal-event-resize" />');
    
    _updateEvent(event, eventDiv);
  }
}