// Android 11 and older: the widget's list fetches its rows through this
// service (Android 12+ gets them all at once, see BoardWidgetProvider).
package com.arunvijey.subwayboard.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService

class BoardWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        Rows(applicationContext, intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID))
}

private class Rows(private val c: Context, private val widgetId: Int) : RemoteViewsService.RemoteViewsFactory {
    private var rows: WidgetRows? = null
    private var items: List<Item> = emptyList()

    override fun onCreate() {}
    override fun onDestroy() {}
    override fun getCount() = items.size
    override fun getViewTypeCount() = ROW_TYPES
    override fun getItemId(position: Int) = position.toLong()
    override fun hasStableIds() = false
    override fun getLoadingView(): RemoteViews? = null

    override fun onDataSetChanged() {
        val w = BoardWidgetProvider.size(AppWidgetManager.getInstance(c), widgetId).first
        val r = WidgetRows(c, w)
        rows = r
        items = r.build(WidgetStore.sel(c), WidgetStore.week(c))
    }

    override fun getViewAt(position: Int): RemoteViews {
        val r = rows ?: WidgetRows(c, 250).also { rows = it }
        return r.view(items.getOrNull(position) ?: Item.Msg(""))
    }
}
