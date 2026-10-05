# frozen_string_literal: true

# Shared aggregation for the release-time audit runners (E71-07, E71-08): one named check per tool
# or scenario directory, one combined report, non-zero exit unless every check passed.

module AuditReport
  Check = Struct.new(:name, :status, :detail, keyword_init: true) do
    def pass? = status == :pass
  end

  module_function

  def pass(name, detail = '') = Check.new(name: name, status: :pass, detail: detail)

  def fail(name, detail) = Check.new(name: name, status: :fail, detail: detail)

  def ok?(checks) = !checks.empty? && checks.all?(&:pass?)

  def render(title, checks)
    lines = checks.map do |c|
      line = format('%-4s %s', c.pass? ? 'PASS' : 'FAIL', c.name)
      c.pass? || c.detail.to_s.empty? ? line : "#{line}\n     #{c.detail}"
    end
    failed = checks.reject(&:pass?).map(&:name)
    verdict = if checks.empty?
                "#{title}: FAILED (no checks ran)"
              elsif failed.empty?
                "#{title}: #{checks.size} check(s) passed"
              else
                "#{title}: FAILED (#{failed.join(', ')})"
              end
    (lines + [verdict]).join("\n")
  end
end
