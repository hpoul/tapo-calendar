import 'package:polymer/polymer.dart';
import 'dart:html';

import 'package:tapo_calendar/calendarview/calendarview.dart';

@CustomTag('tapo-calendar-eventlist')
class EventListElement extends PolymerElement {
  
  
  CalendarView get calendarView =>
      this.getShadowRoot('tapo-calendar-eventlist').query('tapo-calendar-calendarview').xtag;
  
  void clickedZoomIn() {
    calendarView.zoomIn();
  }
  void clickedZoomOut() {
    calendarView.zoomOut();
  }
  
  void inserted() {
    super.inserted();
    
    DateTime date = new DateTime.now();
    DateTime start = new DateTime(date.year, date.month, date.day, 7);
    DateTime end = new DateTime(date.year, date.month, date.day, 7, 45);
    calendarView.events = [new Event(1, start, end, title, 'uh yeah.')];
  }
}