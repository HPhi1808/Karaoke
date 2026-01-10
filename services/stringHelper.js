/**
 * Hàm làm sạch tên người dùng
 * @param {Object} actor - Object chứa thông tin user
 * @returns {String} Tên đã được làm sạch
 */
const getSafeActorName = (actor) => {
  let rawName = actor?.full_name || actor?.username || "Một người dùng";

  let safeName = String(rawName);

  safeName = safeName.replace(/[\x00-\x1F\x7F]/g, "");

  safeName = safeName.trim().replace(/\s+/g, " ");

  if (safeName.length === 0) {
    return "Một người dùng";
  }

  const MAX_LENGTH = 30;
  if (safeName.length > MAX_LENGTH) {
    safeName = safeName.substring(0, MAX_LENGTH - 3) + "...";
  }

  return safeName;
};

module.exports = {getSafeActorName};