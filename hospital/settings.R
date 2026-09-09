# Paths may use a drive letter (X:/...) or UNC path (//server/share/...).
# Relative paths are relative to the extracted tool folder, not R's working directory.
# The demo ignores input_file and config_file. Set mode to "local" for your export.
hospital_settings <- list(
  mode = "demo",
  input_file = "",
  config_file = "config/hospital.example.dcf",
  output_parent = "outputs"
)
