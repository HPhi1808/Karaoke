// services/eventService.js
const { getSupabaseClient } = require('../config/supabaseClient');

const TABLE = 'events';


async function createEvent(data) {
    const { title, description, color1, color2, start_date, end_date, rewards } = data;
    const supabase = getSupabaseClient();

    const { data: result, error } = await supabase
        .from(TABLE)
        .insert([{ title, description, color1, color2, start_date, end_date, rewards }])
        .select();

    if (error) throw new Error(error.message);

    return result && result.length > 0 ? result[0] : null;
}

async function getAllEvents() {
    const supabase = getSupabaseClient();
    const { data, error } = await supabase.from(TABLE).select('*').order('created_at', { ascending: false });
    if (error) throw new Error(error.message);
    return data;
}

async function getEventById(id) {
    const supabase = getSupabaseClient();
    const { data, error } = await supabase.from(TABLE).select('*').eq('id', id).single();
    if (error) throw new Error(error.message);
    return data;
}


async function updateEvent(id, update) {
    const { title, description, color1, color2, start_date, end_date, rewards } = update;
    const supabase = getSupabaseClient();

    const { data, error } = await supabase
        .from(TABLE)
        .update({ title, description, color1, color2, start_date, end_date, rewards })
        .eq('id', id)
        .select();

    if (error) throw new Error(error.message);

    return data && data.length > 0 ? data[0] : null;
}

async function deleteEvent(id) {
    const supabase = getSupabaseClient();
    const { error } = await supabase.from(TABLE).delete().eq('id', id);
    if (error) throw new Error(error.message);
    return { success: true };
}

module.exports = {
    createEvent,
    getAllEvents,
    getEventById,
    updateEvent,
    deleteEvent
};
