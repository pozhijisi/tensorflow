include (ExternalProject)

set(tensorboard_dependencies)
add_custom_target(tensorboard_copy_dependencies)

function(tb_new_http_archive)
  cmake_parse_arguments(_TB "" "NAME;URL" "FILES" ${ARGN})
  ExternalProject_Add(${_TB_NAME}
    PREFIX ${_TB_NAME}
    URL ${_TB_URL}
    DOWNLOAD_DIR "${DOWNLOAD_LOCATION}/${_TB_NAME}"
    CONFIGURE_COMMAND ""
    BUILD_COMMAND ""
    INSTALL_COMMAND ""
  )

  set(src_dir "${CMAKE_CURRENT_BINARY_DIR}/${_TB_NAME}/src/${_TB_NAME}")
  set(dst_dir "${CMAKE_CURRENT_BINARY_DIR}/tensorboard_external/${_TB_NAME}")

  foreach(src_file ${_TB_FILES})
    add_custom_command(
      TARGET tensorboard_copy_dependencies PRE_BUILD
      COMMAND ${CMAKE_COMMAND} -E copy ${src_dir}/${src_file} ${dst_dir}/${src_file}
    )
  endforeach()
  
  set(tensorboard_dependencies ${tensorboard_dependencies} ${_TB_NAME} PARENT_SCOPE)
endfunction()

function(tb_http_file)
  cmake_parse_arguments(_TB "" "NAME;URL" "" ${ARGN})
  get_filename_component(src_file ${_TB_URL} NAME)
  file(DOWNLOAD ${_TB_URL} "${DOWNLOAD_LOCATION}/${_TB_NAME}/${src_file}")
  
  set(src_dir "${DOWNLOAD_LOCATION}/${_TB_NAME}")
  set(dst_dir "${CMAKE_CURRENT_BINARY_DIR}/tensorboard_external/${_TB_NAME}/file")
  
  add_custom_command(
    TARGET tensorboard_copy_dependencies PRE_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy ${src_dir}/${src_file} ${dst_dir}/${src_file}
  )
  
  add_custom_target(${_TB_NAME} DEPENDS ${src_dir}/${src_file})
  set(tensorboard_dependencies ${tensorboard_dependencies} ${_TB_NAME} PARENT_SCOPE)
endfunction()

# Parse TensorBoard dependency names and URLs from Bazel's WORKSPACE file.
set(tb_dep_names)
file(STRINGS ${PROJECT_SOURCE_DIR}/../../../WORKSPACE workspace_contents)
foreach(line ${workspace_contents})
  if(line MATCHES "# TENSORBOARD_BOWER_AUTOGENERATED_BELOW_THIS_LINE_DO_NOT_EDIT")
    set(tb_deps_started 1)
  endif()

  if(NOT tb_deps_started)
    continue()
  endif()

  if(line MATCHES "new_http_archive\\(")
    set(tb_dep_is_archive 1)
    continue()
  elseif(line MATCHES "http_file\\(")
    set(tb_dep_is_archive 0)
    continue()
  endif()

  string(REGEX MATCH "name.*=.*\"(.*)\"" has_name ${line})
  if(has_name)
    set(tb_dep_name ${CMAKE_MATCH_1})
    continue()
  endif()

  string(REGEX MATCH "url.*=.*\"(.*)\"" has_url ${line})
  if(has_url)
    list(APPEND tb_dep_names ${tb_dep_name})
    set(${tb_dep_name}_is_archive ${tb_dep_is_archive})
    set(${tb_dep_name}_url ${CMAKE_MATCH_1})
  endif()
endforeach()

# Parse the files needed for each TensorBoard dependency from Bazel's bower.BUILD file.
# Due to CMAKE quirkiness, cannot use file(strings) with files that contain '[' and ']'.
file(READ ${PROJECT_SOURCE_DIR}/../../../bower.BUILD bower_build_contents)
string(REPLACE "\[" "OB" bower_build_contents "${bower_build_contents}")
string(REPLACE "\]" "CB" bower_build_contents "${bower_build_contents}")
string(REPLACE ";" "\\\\;" bower_build_contents "${bower_build_contents}")
string(REPLACE "\n" "E;" bower_build_contents "${bower_build_contents}")
foreach(line ${bower_build_contents})
  string(REGEX MATCH "name.*=.*\"(.*)\"" has_name ${line})
  if(has_name)
    set(tb_dep_name ${CMAKE_MATCH_1})
    set(${tb_dep_name}_files)
    continue()
  endif()

  string(REGEX MATCH "srcs.*=.*\"(.*)\"CB" has_single_line_src ${line})
  if(has_single_line_src)
    list(APPEND ${tb_dep_name}_files ${CMAKE_MATCH_1})
    continue()
  endif()

  if(line MATCHES "srcs.*=.*OB")
    set(inside_files_def 1)
    continue()
  elseif(line MATCHES "CB,")
    set(inside_files_def 0)
    continue()
  endif()

  if(inside_files_def)
   string(REGEX MATCH "\"(.*)\"," has_file ${line})
   if(has_file)
     list(APPEND ${tb_dep_name}_files ${CMAKE_MATCH_1})
   endif()
  endif()
endforeach()

# Generate a target for each dependency.
foreach(tb_dep_name ${tb_dep_names})
  if (${tb_dep_name}_is_archive)
    tb_new_http_archive(
      NAME ${tb_dep_name}
      URL ${${tb_dep_name}_url}
      FILES ${${tb_dep_name}_files}
    )
  else()
    tb_http_file(
      NAME ${tb_dep_name}
      URL ${${tb_dep_name}_url}
    )
  endif()
endforeach()

add_dependencies(tensorboard_copy_dependencies ${tensorboard_dependencies})
