from flask import Flask, render_template_string, request
import os
import pandas as pd
import plotly.graph_objects as go
from plotly.subplots import make_subplots

app = Flask(__name__)

WORKDIR = "/workspace"

color_dict = {
    'insecure': 'lightgreen',
    'weave': 'darkturquoise',
    'snb': 'orange',
    'opaque': 'red'
}

def clean_and_type(series):
    if series.str.contains('%').any():
        numeric = series.str.replace('%', '', regex=False).astype(float)
        label_type = 'percentage'
    elif series.str.contains('x').any():
        numeric = series.str.replace('x', '', regex=False).astype(float)
        label_type = 'times'
    elif pd.to_numeric(series, errors='coerce').notnull().all():
        numeric = pd.to_numeric(series)
        label_type = 'absolute'
    else:
        return series, 'string'
    return numeric, label_type

def classify(name):
    name = name.lower()
    if 'weave' in name:
        return 'weave'
    elif 'snb' in name:
        return 'snb'
    elif 'columnsort' in name:
        return 'opaque'
    else:
        return 'insecure'

@app.route("/", methods=["GET"])
def single_plot():
    csvs = [f for f in os.listdir(WORKDIR) if f.endswith(".csv")]
    selected_file = request.args.get("file", csvs[0] if csvs else None)
    x = request.args.get("x")
    y = request.args.get("y")
    columns = []
    fig_html = None

    if selected_file:
        df = pd.read_csv(os.path.join(WORKDIR, selected_file))
        columns = df.columns.tolist()

        if x in columns and y in columns:
            df = df[[x, y]].dropna()
            df[x] = df[x].astype(str).apply(lambda val: val[-25:] if len(val) > 25 else val)
            df[y] = df[y].astype(str).apply(lambda val: val[-25:] if len(val) > 25 else val)
            df[y], ytype = clean_and_type(df[y])
            df = df.dropna()
            df['system'] = df[x].apply(classify)

            fig = go.Figure()
            for system in df['system'].unique():
                sub_df = df[df['system'] == system]
                fig.add_trace(go.Bar(x=sub_df[x], y=sub_df[y], name=system, marker_color=color_dict.get(system, 'gray')))

            ylabel = f"{y} ({ytype})" if ytype != 'string' else y
            fig.update_layout(barmode='group', yaxis=dict(title=ylabel, rangemode='tozero'), xaxis=dict(title=x))
            fig_html = fig.to_html(full_html=False)

    return render_template_string("""
<!DOCTYPE html>
<html>
<head>
  <title>🧵 Single CSV Plot</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='0.9em' font-size='90'>🧵</text></svg>">
</head>
<body>
<h2>🧵 CSV Single Plot Viewer</h2>
<form method="get">
  <label>Select CSV:</label>
  <select name="file">
    {% for csv in csvs %}<option value="{{ csv }}" {% if csv == selected_file %}selected{% endif %}>{{ csv }}</option>{% endfor %}
  </select>
  <label>X:</label>
  <select name="x">{% for col in columns %}<option value="{{ col }}" {% if col == x %}selected{% endif %}>{{ col }}</option>{% endfor %}</select>
  <label>Y:</label>
  <select name="y">{% for col in columns %}<option value="{{ col }}" {% if col == y %}selected{% endif %}>{{ col }}</option>{% endfor %}</select>
  <button type="submit">Plot</button>
</form>
{% if fig_html %}<h3>🧵 Plot</h3>{{ fig_html|safe }}{% endif %}
<p><a href="/plot-array">🧵 Go to Multi-Plot View</a></p>
</body>
</html>
""", csvs=csvs, selected_file=selected_file, x=x, y=y, columns=columns, fig_html=fig_html)

@app.route("/plot-array", methods=["GET"])
def plot_array():
    csvs = [f for f in os.listdir(WORKDIR) if f.endswith(".csv")]
    grid_x = int(request.args.get("grid_x", 2))
    grid_y = int(request.args.get("grid_y", 2))

    form_fields = ""
    for r in range(1, grid_y + 1):
        for c in range(1, grid_x + 1):
            fname = request.args.get(f"file_{r}_{c}")
            cols = []
            if fname and fname in csvs:
                try:
                    cols = pd.read_csv(os.path.join(WORKDIR, fname), nrows=1).columns.tolist()
                except: pass
            form_fields += "<div style='border:1px solid #ccc; padding:10px; margin:5px'>"
            form_fields += f"<strong>Plot ({r},{c})</strong><br>"
            form_fields += f"File: <select name='file_{r}_{c}'>"
            for csv in csvs:
                selected = 'selected' if csv == fname else ''
                form_fields += f"<option value='{csv}' {selected}>{csv}</option>"
            form_fields += "</select><br>"
            form_fields += f"X: <select name='x_{r}_{c}'>"
            for col in cols:
                form_fields += f"<option value='{col}'>{col}</option>"
            form_fields += "</select><br>"
            form_fields += f"Y: <select name='y_{r}_{c}'>"
            for col in cols:
                form_fields += f"<option value='{col}'>{col}</option>"
            form_fields += "</select><br></div>"

    fig = make_subplots(rows=grid_y, cols=grid_x)
    for r in range(1, grid_y+1):
        for c in range(1, grid_x+1):
            key = f"file_{r}_{c}"
            xkey = f"x_{r}_{c}"
            ykey = f"y_{r}_{c}"
            fname = request.args.get(key)
            x = request.args.get(xkey)
            y = request.args.get(ykey)

            if not (fname and x and y):
                continue
            try:
                df = pd.read_csv(os.path.join(WORKDIR, fname))
                df = df[[x, y]].dropna()
                df[x] = df[x].astype(str).apply(lambda val: val[-25:] if len(val) > 25 else val)
                df[y] = df[y].astype(str).apply(lambda val: val[-25:] if len(val) > 25 else val)
                df[y], ytype = clean_and_type(df[y])
                df = df.dropna()
                df['system'] = df[x].apply(classify)
                for system in df['system'].unique():
                    sub_df = df[df['system'] == system]
                    fig.add_trace(go.Bar(x=sub_df[x], y=sub_df[y], name=f"{system} ({r},{c})", marker_color=color_dict.get(system, 'gray')),
                                  row=r, col=c)
                fig.update_xaxes(title_text=x, row=r, col=c)
                fig.update_yaxes(title_text=f"{y} ({ytype})" if ytype != 'string' else y, row=r, col=c)
            except Exception:
                continue

    fig.update_layout(height=300*grid_y, width=400*grid_x, barmode='group', showlegend=True)
    fig_html = fig.to_html(full_html=False)

    return render_template_string("""
    <!DOCTYPE html>
    <html><head><title>🧵 CSV Plot Array</title></head><body>
    <h2>🧵 Multi-Plot Builder</h2>
    <form method='get'>
      <label>Grid Size:</label>
      <input type='number' name='grid_x' value='{{ grid_x }}' min='1' max='5'> x
      <input type='number' name='grid_y' value='{{ grid_y }}' min='1' max='5'>
      <button type='submit'>Update Grid</button>
      <hr>
      {{ form_fields|safe }}
      <br><button type='submit'>Generate Plots</button>
    </form>
    <p><a href='/'>🧵 Back to Single Plot</a></p>
    <div>{{ fig_html|safe }}</div>
    </body></html>
    """, grid_x=grid_x, grid_y=grid_y, form_fields=form_fields, fig_html=fig_html)

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=9090)