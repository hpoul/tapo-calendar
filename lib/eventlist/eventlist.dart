library eventlist;

import 'package:polymer/polymer.dart';
import 'dart:html';

import 'package:tapo_calendar/calendarview/calendarview.dart';

@CustomTag('tapo-calendar-eventlist')
class EventListElement extends PolymerElement {
  
  EventListElement.created() : super.created();
  
  CalendarView get calendarView =>
      this.getShadowRoot('tapo-calendar-eventlist').querySelector('tapo-calendar-calendarview');
  
  void clickedZoomIn() {
    calendarView.zoomIn();
  }
  void clickedZoomOut() {
    calendarView.zoomOut();
  }

}