module ignore

import os

const matched_path_or_any_parents_fixture = '# Based on https://github.com/behnam/gitignore-test/blob/master/.gitignore

### file in root

# MATCH /file_root_1
file_root_00

# NO_MATCH
file_root_01/

# NO_MATCH
file_root_02/*

# NO_MATCH
file_root_03/**


# MATCH /file_root_10
/file_root_10

# NO_MATCH
/file_root_11/

# NO_MATCH
/file_root_12/*

# NO_MATCH
/file_root_13/**


# NO_MATCH
*/file_root_20

# NO_MATCH
*/file_root_21/

# NO_MATCH
*/file_root_22/*

# NO_MATCH
*/file_root_23/**


# MATCH /file_root_30
**/file_root_30

# NO_MATCH
**/file_root_31/

# NO_MATCH
**/file_root_32/*

# NO_MATCH
**/file_root_33/**


### file in sub-dir

# MATCH /parent_dir/file_deep_1
file_deep_00

# NO_MATCH
file_deep_01/

# NO_MATCH
file_deep_02/*

# NO_MATCH
file_deep_03/**


# NO_MATCH
/file_deep_10

# NO_MATCH
/file_deep_11/

# NO_MATCH
/file_deep_12/*

# NO_MATCH
/file_deep_13/**


# MATCH /parent_dir/file_deep_20
*/file_deep_20

# NO_MATCH
*/file_deep_21/

# NO_MATCH
*/file_deep_22/*

# NO_MATCH
*/file_deep_23/**


# MATCH /parent_dir/file_deep_30
**/file_deep_30

# NO_MATCH
**/file_deep_31/

# NO_MATCH
**/file_deep_32/*

# NO_MATCH
**/file_deep_33/**


### dir in root

# MATCH /dir_root_00
dir_root_00

# MATCH /dir_root_01
dir_root_01/

# MATCH /dir_root_02
dir_root_02/*

# MATCH /dir_root_03
dir_root_03/**


# MATCH /dir_root_10
/dir_root_10

# MATCH /dir_root_11
/dir_root_11/

# MATCH /dir_root_12
/dir_root_12/*

# MATCH /dir_root_13
/dir_root_13/**


# NO_MATCH
*/dir_root_20

# NO_MATCH
*/dir_root_21/

# NO_MATCH
*/dir_root_22/*

# NO_MATCH
*/dir_root_23/**


# MATCH /dir_root_30
**/dir_root_30

# MATCH /dir_root_31
**/dir_root_31/

# MATCH /dir_root_32
**/dir_root_32/*

# MATCH /dir_root_33
**/dir_root_33/**


### dir in sub-dir

# MATCH /parent_dir/dir_deep_00
dir_deep_00

# MATCH /parent_dir/dir_deep_01
dir_deep_01/

# NO_MATCH
dir_deep_02/*

# NO_MATCH
dir_deep_03/**


# NO_MATCH
/dir_deep_10

# NO_MATCH
/dir_deep_11/

# NO_MATCH
/dir_deep_12/*

# NO_MATCH
/dir_deep_13/**


# MATCH /parent_dir/dir_deep_20
*/dir_deep_20

# MATCH /parent_dir/dir_deep_21
*/dir_deep_21/

# MATCH /parent_dir/dir_deep_22
*/dir_deep_22/*

# MATCH /parent_dir/dir_deep_23
*/dir_deep_23/**


# MATCH /parent_dir/dir_deep_30
**/dir_deep_30

# MATCH /parent_dir/dir_deep_31
**/dir_deep_31/

# MATCH /parent_dir/dir_deep_32
**/dir_deep_32/*

# MATCH /parent_dir/dir_deep_33
**/dir_deep_33/**
'

fn gitignore_for_matched_path_or_any_parents() Gitignore {
	mut builder := GitignoreBuilder.new('ROOT')
	add_has_err, add_err := builder.add_str(none_string(), matched_path_or_any_parents_fixture)
	assert !add_has_err, add_err.msg()
	gi, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	return gi
}

fn assert_parent_match(gitignore &Gitignore, path string, is_dir bool, ignored bool) {
	matched := gitignore.matched_path_or_any_parents(path, is_dir)
	if ignored {
		assert matched.is_ignore()
	} else {
		assert matched.is_none()
	}
}

fn assert_parent_dir_tree(gitignore &Gitignore, path string, self_ignored bool, child_ignored bool) {
	assert_parent_match(gitignore, path, true, self_ignored)
	assert_parent_match(gitignore, '${path}/file', false, child_ignored)
	assert_parent_match(gitignore, '${path}/child_dir', true, child_ignored)
	assert_parent_match(gitignore, '${path}/child_dir/file', false, child_ignored)
}

fn test_gitignore_skip_bom() {
	td := tmpdir()
	defer {
		td.cleanup()
	}
	path := os.join_path(td.path(), 'ignore')
	bytes := [u8(0xef), 0xbb, 0xbf, `i`, `g`, `n`, `o`, `r`, `e`, `/`, `t`, `h`, `i`,
		`s`, `/`, `p`, `a`, `t`, `h`, `\n`]
	os.write_file(path, bytes.bytestr()) or { panic(err.msg()) }
	mut builder := GitignoreBuilder.new('ROOT')
	add_has_err, add_err := builder.add(path)
	assert !add_has_err, add_err.msg()
	gi, build_has_err, build_err := builder.build()
	assert !build_has_err, build_err.msg()
	assert gi.matched('ignore/this/path', false).is_ignore()
}

fn test_matched_path_or_any_parents_files_in_root() {
	gitignore := gitignore_for_matched_path_or_any_parents()

	// 0x
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_00', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_01', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_02', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_03', false).is_none()

	// 1x
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_10', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_11', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_12', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_13', false).is_none()

	// 2x
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_20', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_21', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_22', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_23', false).is_none()

	// 3x
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_30', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_31', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_32', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/file_root_33', false).is_none()
}

fn test_matched_path_or_any_parents_files_in_deep() {
	gitignore := gitignore_for_matched_path_or_any_parents()

	// 0x
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_00', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_01', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_02', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_03', false).is_none()

	// 1x
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_10', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_11', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_12', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_13', false).is_none()

	// 2x
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_20', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_21', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_22', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_23', false).is_none()

	// 3x
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_30', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_31', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_32', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/file_deep_33', false).is_none()
}

fn test_matched_path_or_any_parents_dirs_in_root() {
	gitignore := gitignore_for_matched_path_or_any_parents()

	// 00
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_00', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_00/file', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_00/child_dir', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_00/child_dir/file',
		false).is_ignore()

	// 01
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_01', true, true)

	// 02
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_02', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_02/file', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_02/child_dir', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_02/child_dir/file',
		false).is_ignore()

	// 03
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_03', false, true)

	// 10
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_10', true, true)

	// 11
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_11', true, true)

	// 12
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_12', false, true)

	// 13
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_13', false, true)

	// 20
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_20', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_20/file', false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_20/child_dir', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_20/child_dir/file',
		false).is_none()

	// 21
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_21', false, false)

	// 22
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_22', false, false)

	// 23
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_23', false, false)

	// 30
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_30', true, true)

	// 31
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_31', true, true)

	// 32
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_32', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_32/file', false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_32/child_dir', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/dir_root_32/child_dir/file',
		false).is_ignore()

	// 33
	assert_parent_dir_tree(&gitignore, 'ROOT/dir_root_33', false, true)
}

fn test_matched_path_or_any_parents_dirs_in_deep() {
	gitignore := gitignore_for_matched_path_or_any_parents()

	// 00
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_00', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_00/file',
		false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_00/child_dir',
		true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_00/child_dir/file',
		false).is_ignore()

	// 01
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_01', true, true)

	// 02
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_02', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_02/file',
		false).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_02/child_dir',
		true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_02/child_dir/file',
		false).is_none()

	// 03
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_03', false, false)

	// 10
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_10', false, false)

	// 11
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_11', false, false)

	// 12
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_12', false, false)

	// 13
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_13', false, false)

	// 20
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_20', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_20/file',
		false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_20/child_dir',
		true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_20/child_dir/file',
		false).is_ignore()

	// 21
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_21', true, true)

	// 22
	// dir itself doesn't match
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_22', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_22/file',
		false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_22/child_dir',
		true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_22/child_dir/file',
		false).is_ignore()

	// 23
	// dir itself doesn't match
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_23', false, true)

	// 30
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_30', true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_30/file',
		false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_30/child_dir',
		true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_30/child_dir/file',
		false).is_ignore()

	// 31
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_31', true, true)

	// 32
	// dir itself doesn't match
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_32', true).is_none()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_32/file',
		false).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_32/child_dir',
		true).is_ignore()
	assert gitignore.matched_path_or_any_parents('ROOT/parent_dir/dir_deep_32/child_dir/file',
		false).is_ignore()

	// 33
	// dir itself doesn't match
	assert_parent_dir_tree(&gitignore, 'ROOT/parent_dir/dir_deep_33', false, true)
}
